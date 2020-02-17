defmodule Commanded.Aggregates.AggregateTest do
  use ExUnit.Case

  import ExUnit.CaptureLog

  alias Commanded.Aggregates.Aggregate
  alias Commanded.Aggregates.ExecutionContext
  alias Commanded.DefaultApp

  defmodule RaiseException do
    defstruct [:message]
  end

  defmodule ExampleAggregate do
    defstruct [:uuid]

    def execute(%ExampleAggregate{}, %RaiseException{message: message}) do
      raise message
    end
  end

  setup do
    start_supervised!(DefaultApp)
    :ok
  end

  describe "aggregate process" do
    setup do
      aggregate_uuid = UUID.uuid4()

      {:ok, pid} = start_aggregate(aggregate_uuid)

      ref = Process.monitor(pid)
      Process.unlink(pid)

      [aggregate_uuid: aggregate_uuid, pid: pid, ref: ref]
    end

    test "ignore unexpected messages", %{pid: pid, ref: ref} do
      send_unexpected_mesage = fn ->
        send(pid, :unexpected_message)

        refute_receive {:DOWN, ^ref, :process, ^pid, _reason}
      end

      captured = capture_log(send_unexpected_mesage)

      assert captured =~ "received unexpected message in handle_info/2: :unexpected_message"
    end

    test "log exception", %{pid: pid, ref: ref} do
      raise_exception = fn ->
        context = %ExecutionContext{
          command: %RaiseException{message: "an exception"},
          function: :execute,
          handler: ExampleAggregate
        }

        GenServer.call(pid, {:execute_command, context})

        assert_receive {:DOWN, ^ref, :process, ^pid, %RuntimeError{message: "an exception"}}
      end

      captured = capture_log(raise_exception)

      assert captured =~ "(RuntimeError) an exception"
      assert captured =~ "aggregate_test.exs"
      assert captured =~ "Commanded.Aggregates.AggregateTest.ExampleAggregate.execute/2"
    end
  end

  def start_aggregate(aggregate_uuid) do
    Aggregate.start_link([application: DefaultApp],
      aggregate_module: ExampleAggregate,
      aggregate_uuid: aggregate_uuid
    )
  end
end
