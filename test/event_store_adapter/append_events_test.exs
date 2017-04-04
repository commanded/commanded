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
    test "should append events" do
      assert {:ok, 2} == @event_store.append_to_stream("stream", 0, build_events(2))
      assert {:ok, 4} == @event_store.append_to_stream("stream", 2, build_events(2))
      assert {:ok, 5} == @event_store.append_to_stream("stream", 4, build_events(1))
    end

    test "should fail to append to a stream because of wrong expected version when no previous events" do
      events = build_events(1)

      assert {:error, :wrong_expected_version} == @event_store.append_to_stream("stream", 1, events)
    end

    test "should fail to append to a stream because of wrong expected version" do
      assert {:ok, 2} == @event_store.append_to_stream("stream", 0, build_events(2))

      assert {:error, :wrong_expected_version} == @event_store.append_to_stream("stream", 1, build_events(1))
    end
  end

  describe "stream events from a stream" do
    test "should read events" do
      events = build_events(4)

      {:ok, 4} == @event_store.append_to_stream("astream", 0, events)

      read_events = @event_store.stream_forward("astream") |> Enum.to_list()
      assert length(read_events) == 4
      assert coerce(events) == coerce(read_events)

      read_events = @event_store.stream_forward("astream", 3) |> Enum.to_list()
      assert coerce(Enum.slice(events, 2, 2)) == coerce(read_events)
    end

    test "should read from single stream" do
      events1 = build_events(2)
      events2 = build_events(4)

      {:ok, 2} == @event_store.append_to_stream("astream", 0, events1)
      {:ok, 4} == @event_store.append_to_stream("asecondstream", 0, events2)

      read_events = @event_store.stream_forward("astream", 0) |> Enum.to_list()
      assert 2 == length(read_events)
      assert coerce(events1) == coerce(read_events)

      read_events = @event_store.stream_forward("asecondstream", 0) |> Enum.to_list()
      assert 4 == length(read_events)
      assert coerce(events2) == coerce(read_events)
    end
  end

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

  defp coerce(events), do: Enum.map(events, &(%{correlation_id: &1.correlation_id, data: &1.data}))
end
