defmodule Commanded.EventStore.Adapter.AppendEventsTest do
  use Commanded.StorageCase

  import Commanded.Enumerable, only: [pluck: 2]

  alias Commanded.EventStore
  alias Commanded.EventStore.EventData

  defmodule BankAccountOpened, do: defstruct [:account_number, :initial_balance]

  describe "append events to a stream" do
    test "should append events" do
      assert {:ok, 2} == EventStore.append_to_stream("stream", 0, build_events(2))
      assert {:ok, 4} == EventStore.append_to_stream("stream", 2, build_events(2))
      assert {:ok, 5} == EventStore.append_to_stream("stream", 4, build_events(1))
    end

    test "should fail to append to a stream because of wrong expected version when no previous events" do
      events = build_events(1)

      assert {:error, :wrong_expected_version} == EventStore.append_to_stream("stream", 1, events)
    end

    test "should fail to append to a stream because of wrong expected version" do
      assert {:ok, 2} == EventStore.append_to_stream("stream", 0, build_events(2))

      assert {:error, :wrong_expected_version} == EventStore.append_to_stream("stream", 1, build_events(1))
    end
  end

  describe "stream events from an unknown stream" do
    test "should return stream not found error" do
      assert {:error, :stream_not_found} == EventStore.stream_forward("unknownstream")
    end
  end

  describe "stream events from an existing stream" do
    test "should read events" do
      correlation_id = UUID.uuid4()
      causation_id = UUID.uuid4()
      events = build_events(4, correlation_id, causation_id)

      assert {:ok, 4} == EventStore.append_to_stream("stream", 0, events)

      read_events = EventStore.stream_forward("stream") |> Enum.to_list()
      assert length(read_events) == 4
      assert coerce(events) == coerce(read_events)
      assert pluck(read_events, :stream_version) == [1, 2, 3, 4]

      Enum.each(read_events, fn event ->
        assert_is_uuid event.event_id
        assert event.stream_id == "stream"
        assert event.correlation_id == correlation_id
        assert event.causation_id == causation_id
        assert event.metadata == %{"metadata" => "value"}
      end)

      read_events = EventStore.stream_forward("stream", 3) |> Enum.to_list()
      assert coerce(Enum.slice(events, 2, 2)) == coerce(read_events)
      assert pluck(read_events, :stream_version) == [3, 4]
    end

    test "should read from single stream" do
      events1 = build_events(2)
      events2 = build_events(4)

      assert {:ok, 2} == EventStore.append_to_stream("stream", 0, events1)
      assert {:ok, 4} == EventStore.append_to_stream("secondstream", 0, events2)

      read_events = EventStore.stream_forward("stream", 0) |> Enum.to_list()
      assert 2 == length(read_events)
      assert coerce(events1) == coerce(read_events)

      read_events = EventStore.stream_forward("secondstream", 0) |> Enum.to_list()
      assert 4 == length(read_events)
      assert coerce(events2) == coerce(read_events)
    end

    test "should read events in batches" do
      events = build_events(10)

      assert {:ok, 10} == EventStore.append_to_stream("stream", 0, events)

      read_events = EventStore.stream_forward("stream", 0, 2) |> Enum.to_list()
      assert length(read_events) == 10
      assert coerce(events) == coerce(read_events)

      assert pluck(read_events, :stream_version) == [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
    end
  end

  defp build_event(account_number, correlation_id, causation_id) do
    %EventData{
      correlation_id: correlation_id,
      causation_id: causation_id,
      event_type: "Elixir.Commanded.EventStore.Adapter.AppendEventsTest.BankAccountOpened",
      data: %BankAccountOpened{account_number: account_number, initial_balance: 1_000},
      metadata: %{"metadata" => "value"},
    }
  end

  defp build_events(count, correlation_id \\ UUID.uuid4(), causation_id \\ UUID.uuid4())
  defp build_events(count, correlation_id, causation_id) do
    for account_number <- 1..count, do: build_event(account_number, correlation_id, causation_id)
  end

  defp assert_is_uuid(uuid) do
    assert uuid |> UUID.string_to_binary!() |> is_binary()
  end

  defp coerce(events), do: Enum.map(events, &(%{causation_id: &1.causation_id, correlation_id: &1.correlation_id, data: &1.data, metadata: &1.metadata}))
end
