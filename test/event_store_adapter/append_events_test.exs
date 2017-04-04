defmodule Commanded.EventStore.Adapter.AppendEventsTest do
  use Commanded.StorageCase
  use Commanded.EventStore

  alias Commanded.EventStore.{
    EventData,
    SnapshotData,
  }
  alias Commanded.ExampleDomain.BankAccount.Events.BankAccountOpened

  require Logger

  describe "append events to a stream" do
    @tag :wip
    test "should append events" do
      assert {:ok, 2} == @event_store.append_to_stream("stream", 0, build_events(2))
      assert {:ok, 4} == @event_store.append_to_stream("stream", 2, build_events(2))
      assert {:ok, 5} == @event_store.append_to_stream("stream", 4, build_events(1))
    end

    @tag :wip
    test "should fail to append to a stream because of wrong expected version" do
      events = build_events(1)

      assert {:error, :wrong_expected_version} == @event_store.append_to_stream("stream", 1, events)
    end
  end

  # test "should read from a stream" do
  #   events = new_test_events 4
  #   coerce = fn(evs) -> Enum.map(evs, &(%{correlation_id: &1.correlation_id, data: &1.data})) end
  #
  #   assert {:ok, 4} == @event_store.append_to_stream("astream", 0, events)
  #
  #   {:ok, result } = @event_store.read_stream_forward("astream", 1)
  #   assert coerce.(events) == coerce.(result)
  #
  #   {:ok, result } = @event_store.read_stream_forward("astream", 3)
  #   assert coerce.(Enum.slice(events, 2, 2)) == coerce.(result)
  # end
  #
  # test "should read from all streams" do
  #   events1 = new_test_events 4
  #   events2 = new_test_events 4
  #   coerce = fn(evs) -> Enum.map(evs, &(%{correlation_id: &1.correlation_id, data: &1.data})) end
  #
  #   assert {:ok, 4} == @event_store.append_to_stream("astream", 0, events1)
  #   assert {:ok, 4} == @event_store.append_to_stream("asecondstream", 0, events2)
  #
  #   :timer.sleep(500)
  #
  #   {:ok, result } = @event_store.read_all_streams_forward(0)
  #
  #   assert 8 == length(result)
  #   assert coerce.(events1 ++ events2) == coerce.(result)
  # end

  defp build_event(account_number) do
    %EventData{
      correlation_id: UUID.uuid4,
      event_type: "Elixir.Commanded.ExampleDomain.BankAccount.Events.BankAccountOpened",
      data: %BankAccountOpened{account_number: account_number, initial_balance: 1_000},
      metadata: nil
    }
  end

  defp build_events(count) do
    for account_number <- 1..count, do: build_event(account_number)
  end
end
