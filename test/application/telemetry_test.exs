defmodule Commanded.Application.TelemetryTest do
  use ExUnit.Case

  alias Commanded.DefaultApp
  alias Commanded.Middleware.Commands.IncrementCount
  alias Commanded.Middleware.Commands.RaiseError
  alias Commanded.UUID

  setup do
    start_supervised!(DefaultApp)
    attach_telemetry()

    :ok
  end

  defmodule TestRouter do
    use Commanded.Commands.Router

    alias Commanded.Middleware.Commands.CommandHandler
    alias Commanded.Middleware.Commands.CounterAggregateRoot

    dispatch IncrementCount,
      to: CommandHandler,
      aggregate: CounterAggregateRoot,
      identity: :aggregate_uuid

    dispatch RaiseError,
      to: CommandHandler,
      aggregate: CounterAggregateRoot,
      identity: :aggregate_uuid
  end

  test "emit `[:commanded, :application, :dispatch, :start | :stop]` event" do
    command = %IncrementCount{aggregate_uuid: UUID.uuid4()}

    assert :ok = TestRouter.dispatch(command, application: DefaultApp)

    assert_receive {[:commanded, :application, :dispatch, :start], 1, _meas, _meta}
    assert_receive {[:commanded, :aggregate, :execute, :start], 2, _meas, _meta}
    assert_receive {[:commanded, :aggregate, :execute, :stop], 3, _meas, _meta}
    assert_receive {[:commanded, :application, :dispatch, :stop], 4, _meas, meta}

    assert %{application: DefaultApp, error: nil, execution_context: %{command: ^command}} = meta
  end

  test "emit `[:commanded, :application, :dispatch, :start | :stop]` event on error" do
    command = %RaiseError{aggregate_uuid: UUID.uuid4()}
    error = %RuntimeError{message: "failed"}

    assert {:error, ^error} = TestRouter.dispatch(command, application: DefaultApp)

    assert_receive {[:commanded, :application, :dispatch, :start], 1, _meas, _meta}
    assert_receive {[:commanded, :aggregate, :execute, :start], 2, _meas, _meta}
    assert_receive {[:commanded, :aggregate, :execute, :exception], 3, _meas, _meta}
    assert_receive {[:commanded, :application, :dispatch, :stop], 4, _meas, meta}

    assert %{application: DefaultApp, error: ^error, execution_context: %{command: ^command}} =
             meta
  end

  defp attach_telemetry do
    agent = start_supervised!({Agent, fn -> 1 end})

    :telemetry.attach_many(
      "test-handler",
      [
        [:commanded, :aggregate, :execute, :start],
        [:commanded, :aggregate, :execute, :stop],
        [:commanded, :aggregate, :execute, :exception],
        [:commanded, :application, :dispatch, :start],
        [:commanded, :application, :dispatch, :stop]
      ],
      fn event_name, measurements, metadata, reply_to ->
        num = Agent.get_and_update(agent, fn n -> {n, n + 1} end)
        send(reply_to, {event_name, num, measurements, metadata})
      end,
      self()
    )

    on_exit(fn ->
      :telemetry.detach("test-handler")
    end)
  end
end
