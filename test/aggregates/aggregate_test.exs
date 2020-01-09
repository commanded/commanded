defmodule Commanded.Aggregates.AggregateTest do
  use ExUnit.Case, async: true

  alias Commanded.Aggregates.Aggregate
  alias Commanded.DefaultApp

  defmodule ExampleAggregate do
    defstruct [:uuid]
  end

  setup do
    start_supervised!(DefaultApp)
    :ok
  end

  describe "aggregate process" do
    setup do
      aggregate_uuid = UUID.uuid4()

      {:ok, pid} = start_aggregate(aggregate_uuid)

      [aggregate_uuid: aggregate_uuid, pid: pid]
    end

    test "ignore unexpected messages", %{pid: pid} do
      import ExUnit.CaptureLog

      ref = Process.monitor(pid)

      send_unexpected_mesage = fn ->
        send(pid, :unexpected_message)

        refute_receive {:DOWN, ^ref, :process, ^pid, _}
      end

      assert capture_log(send_unexpected_mesage) =~
               "received unexpected message in handle_info/2: :unexpected_message"
    end
  end

  def start_aggregate(aggregate_uuid) do
    Aggregate.start_link([application: DefaultApp],
      application: DefaultApp,
      aggregate_module: ExampleAggregate,
      aggregate_uuid: aggregate_uuid
    )
  end
end
