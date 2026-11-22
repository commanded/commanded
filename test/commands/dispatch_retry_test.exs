defmodule Commanded.Commands.DispatchRetryTest do
  use ExUnit.Case

  alias Commanded.DefaultApp
  alias Commanded.UUID

  defmodule StoppingAggregate do
    @moduledoc false
    defstruct [:uuid]

    defmodule Command do
      @moduledoc false
      defstruct [:uuid, :reply_to, action: :noop]
    end

    def execute(%StoppingAggregate{}, %Command{}), do: []
  end

  defmodule BlockThenStopLifespan do
    @moduledoc false
    @behaviour Commanded.Aggregates.AggregateLifespan

    alias Commanded.Commands.DispatchRetryTest.StoppingAggregate.Command

    # Block the aggregate process until told to continue, then stop it.
    def after_command(%Command{action: :block, reply_to: reply_to}) do
      send(reply_to, {:blocked, self()})

      receive do
        :continue -> :stop
      end
    end

    def after_command(%Command{}), do: :stop

    def after_event(_event), do: :stop
    def after_error(_error), do: :stop
  end

  defmodule StoppingRouter do
    use Commanded.Commands.Router

    alias Commanded.Commands.DispatchRetryTest.BlockThenStopLifespan
    alias Commanded.Commands.DispatchRetryTest.StoppingAggregate
    alias Commanded.Commands.DispatchRetryTest.StoppingAggregate.Command

    dispatch Command, to: StoppingAggregate, identity: :uuid, lifespan: BlockThenStopLifespan
  end

  alias Commanded.Commands.DispatchRetryTest.StoppingAggregate.Command

  setup do
    start_supervised!(DefaultApp)

    :ok
  end

  describe "dispatch to a stopping aggregate" do
    setup do
      reply_to = self()

      :telemetry.attach(
        "dispatch-retry-test-handler",
        [:commanded, :application, :dispatch, :stop],
        fn event_name, _measurements, metadata, _config ->
          send(reply_to, {event_name, metadata})
        end,
        nil
      )

      on_exit(fn -> :telemetry.detach("dispatch-retry-test-handler") end)
    end

    test "should return `{:error, :too_many_attempts}` when retries are exhausted" do
      aggregate_uuid = UUID.uuid4()
      reply_to = self()

      blocking =
        Task.async(fn ->
          command = %Command{uuid: aggregate_uuid, action: :block, reply_to: reply_to}

          StoppingRouter.dispatch(command, application: DefaultApp)
        end)

      assert_receive {:blocked, aggregate_pid}

      # Queue a command behind the blocked one, it will be executed by an
      # aggregate process which stops before handling it.
      queued =
        Task.async(fn ->
          command = %Command{uuid: aggregate_uuid}

          StoppingRouter.dispatch(command, application: DefaultApp, retry_attempts: 0)
        end)

      wait_until_queued(aggregate_pid)

      send(aggregate_pid, :continue)

      assert :ok = Task.await(blocking)
      assert {:error, :too_many_attempts} = Task.await(queued)

      assert_receive {[:commanded, :application, :dispatch, :stop], %{error: nil}}

      assert_receive {[:commanded, :application, :dispatch, :stop], %{error: :too_many_attempts}}
    end
  end

  defp wait_until_queued(pid) do
    case Process.info(pid, :message_queue_len) do
      {:message_queue_len, 0} ->
        Process.sleep(1)
        wait_until_queued(pid)

      {:message_queue_len, _len} ->
        :ok
    end
  end
end
