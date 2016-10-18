defmodule EventStore.Storage.ReadEventsTest do
  use EventStore.StorageCase
  doctest EventStore.Storage

  alias EventStore.EventFactory
  alias EventStore.Storage
  alias EventStore.Storage.{Appender,Stream}

  setup do
    storage_config = Application.get_env(:eventstore, EventStore.Storage)

    {:ok, conn} = Postgrex.start_link(storage_config)
    {:ok, %{conn: conn}}
  end

  describe "read stream forward" do
    test "when stream does not exist" do
      {:ok, []} = Storage.read_stream_forward(1, 0, 1_000)
    end

    test "when empty", %{conn: conn} do
      {:ok, stream_id} = create_stream(conn)

      {:ok, []} = Storage.read_stream_forward(stream_id, 0, 1_000)
    end

    test "with single event", %{conn: conn} do
      {:ok, stream_id} = create_stream_containing_events(conn, 1)

      {:ok, read_events} = Storage.read_stream_forward(stream_id, 0, 1_000)

      read_event = hd(read_events)
      recorded_event = hd(EventFactory.create_recorded_events(1, stream_id))

      assert read_event.event_id == 1
      assert read_event.stream_id == 1
      assert read_event.data == recorded_event.data
      assert read_event.metadata == recorded_event.metadata
    end

    test "with multiple events from origin limited by count", %{conn: conn} do
      {:ok, stream_id} = create_stream_containing_events(conn, 10)

      {:ok, read_events} = Storage.read_stream_forward(stream_id, 0, 5)

      assert length(read_events) == 5
      assert pluck(read_events, :event_id) == Enum.to_list(1..5)
    end

    test "with multiple events from stream version limited by count", %{conn: conn} do
      {:ok, stream_id} = create_stream_containing_events(conn, 10)

      {:ok, read_events} = Storage.read_stream_forward(stream_id, 6, 5)

      assert length(read_events) == 5
      assert pluck(read_events, :event_id) == Enum.to_list(6..10)
    end
  end

  describe "read all streams forward" do
    test "when no streams exist" do
      {:ok, []} = Storage.read_all_streams_forward(0, 1_000)
    end

    test "with multiple events", %{conn: conn} do
      {:ok, stream1_id} = create_stream(conn)
      {:ok, stream2_id} = create_stream(conn)

      {:ok, 1} = Appender.append(conn, stream1_id, EventFactory.create_recorded_events(1, stream1_id))
      {:ok, 1} = Appender.append(conn, stream2_id, EventFactory.create_recorded_events(1, stream2_id, 2))
      {:ok, 1} = Appender.append(conn, stream1_id, EventFactory.create_recorded_events(1, stream1_id, 3, 2))
      {:ok, 1} = Appender.append(conn, stream2_id, EventFactory.create_recorded_events(1, stream2_id, 4, 2))

      {:ok, events} = Storage.read_all_streams_forward(0, 1_000)

      assert length(events) == 4
      assert [1, 2, 3, 4] == Enum.map(events, &(&1.event_id))
      assert [1, 2, 1, 2] == Enum.map(events, &(&1.stream_id))
      assert [1, 1, 2, 2] == Enum.map(events, &(&1.stream_version))
    end

    test "with multiple events from after last event", %{conn: conn} do
      {:ok, stream1_id} = create_stream(conn)
      {:ok, stream2_id} = create_stream(conn)

      {:ok, 1} = Appender.append(conn, stream1_id, EventFactory.create_recorded_events(1, stream1_id))
      {:ok, 1} = Appender.append(conn, stream2_id, EventFactory.create_recorded_events(1, stream2_id, 2))

      {:ok, events} = Storage.read_all_streams_forward(3, 1_000)

      assert length(events) == 0
    end

    test "with multiple events from after last event limited by count", %{conn: conn} do
      {:ok, stream1_id} = create_stream(conn)
      {:ok, stream2_id} = create_stream(conn)

      {:ok, 5} = Appender.append(conn, stream1_id, EventFactory.create_recorded_events(5, stream1_id))
      {:ok, 5} = Appender.append(conn, stream2_id, EventFactory.create_recorded_events(5, stream2_id, 6))
      {:ok, 5} = Appender.append(conn, stream1_id, EventFactory.create_recorded_events(5, stream1_id, 11, 6))
      {:ok, 5} = Appender.append(conn, stream2_id, EventFactory.create_recorded_events(5, stream2_id, 16, 6))

      {:ok, events} = Storage.read_all_streams_forward(0, 10)

      assert length(events) == 10
      assert pluck(events, :event_id) == Enum.to_list(1..10)

      {:ok, events} = Storage.read_all_streams_forward(11, 10)

      assert length(events) == 10
      assert pluck(events, :event_id) == Enum.to_list(11..20)
    end
  end

  describe "query latest event id" do
    test "when no events" do
      {:ok, latest_event_id} = Storage.latest_event_id

      assert latest_event_id == 0
    end

    test "when events exist", %{conn: conn}do
      {:ok, _stream_id} = create_stream_containing_events(conn, 3)

      {:ok, latest_event_id} = Storage.latest_event_id

      assert latest_event_id == 3
    end
  end

  defp create_stream(conn), do: Stream.create_stream(conn, UUID.uuid4)

  defp create_stream_containing_events(conn, event_count) do
    {:ok, stream_id} = create_stream(conn)
    recorded_events = EventFactory.create_recorded_events(event_count, stream_id)
    {:ok, ^event_count} = Appender.append(conn, stream_id, recorded_events)
    {:ok, stream_id}
  end

  defp pluck(enumerable, field), do: Enum.map(enumerable, &Map.get(&1, field))
end
