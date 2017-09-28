defmodule EventStore.Storage.ReadEventsTest do
  use EventStore.StorageCase
  doctest EventStore.Storage

  alias EventStore.EventFactory
  alias EventStore.Storage
  alias EventStore.Storage.{Appender,Stream}

  describe "read stream forward" do
    test "when stream does not exist" do
      {:ok, []} = Storage.read_stream_forward(1, 0, 1_000)
    end

    test "when empty", %{conn: conn} do
      {:ok, _stream_uuid, stream_id} = create_stream(conn)

      assert {:ok, []} = Storage.read_stream_forward(stream_id, 0, 1_000)
    end

    test "with single event", %{conn: conn} do
      {:ok, stream_uuid, stream_id} = create_stream_containing_events(conn, 1)

      {:ok, read_events} = Storage.read_stream_forward(stream_id, 0, 1_000)

      read_event = hd(read_events)
      recorded_event = hd(EventFactory.create_recorded_events(1, stream_uuid))

      assert read_event.event_id == 1
      assert read_event.stream_uuid == stream_uuid
      assert read_event.data == recorded_event.data
      assert read_event.metadata == recorded_event.metadata
    end

    test "with multiple events from origin limited by count", %{conn: conn} do
      {:ok, _stream_uuid, stream_id} = create_stream_containing_events(conn, 10)

      {:ok, read_events} = Storage.read_stream_forward(stream_id, 0, 5)

      assert length(read_events) == 5
      assert pluck(read_events, :event_id) == Enum.to_list(1..5)
    end

    test "with multiple events from stream version limited by count", %{conn: conn} do
      {:ok, _stream_uuid, stream_id} = create_stream_containing_events(conn, 10)

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
      {:ok, stream1_uuid, stream1_id} = create_stream(conn)
      {:ok, stream2_uuid, stream2_id} = create_stream(conn)

      {:ok, [1]} = Appender.append(conn, stream1_id, EventFactory.create_recorded_events(1, stream1_uuid))
      {:ok, [2]} = Appender.append(conn, stream2_id, EventFactory.create_recorded_events(1, stream2_uuid, 2))
      {:ok, [3]} = Appender.append(conn, stream1_id, EventFactory.create_recorded_events(1, stream1_uuid, 3, 2))
      {:ok, [4]} = Appender.append(conn, stream2_id, EventFactory.create_recorded_events(1, stream2_uuid, 4, 2))

      {:ok, events} = Storage.read_all_streams_forward(0, 1_000)

      assert length(events) == 4
      assert [1, 2, 3, 4] == Enum.map(events, &(&1.event_id))
      assert [stream1_uuid, stream2_uuid, stream1_uuid, stream2_uuid] == Enum.map(events, &(&1.stream_uuid))
      assert [1, 1, 2, 2] == Enum.map(events, &(&1.stream_version))
    end

    test "with multiple events from after last event", %{conn: conn} do
      {:ok, stream1_uuid, stream1_id} = create_stream(conn)
      {:ok, stream2_uuid, stream2_id} = create_stream(conn)

      {:ok, [1]} = Appender.append(conn, stream1_id, EventFactory.create_recorded_events(1, stream1_uuid))
      {:ok, [2]} = Appender.append(conn, stream2_id, EventFactory.create_recorded_events(1, stream2_uuid, 2))

      {:ok, events} = Storage.read_all_streams_forward(3, 1_000)

      assert length(events) == 0
    end

    test "with multiple events from after last event limited by count", %{conn: conn} do
      {:ok, stream1_uuid, stream1_id} = create_stream(conn)
      {:ok, stream2_uuid, stream2_id} = create_stream(conn)

      {:ok, [1, 2, 3, 4, 5]} = Appender.append(conn, stream1_id, EventFactory.create_recorded_events(5, stream1_uuid))
      {:ok, [6, 7, 8, 9, 10]} = Appender.append(conn, stream2_id, EventFactory.create_recorded_events(5, stream2_uuid, 6))
      {:ok, [11, 12, 13, 14, 15]} = Appender.append(conn, stream1_id, EventFactory.create_recorded_events(5, stream1_uuid, 11, 6))
      {:ok, [16, 17, 18, 19, 20]} = Appender.append(conn, stream2_id, EventFactory.create_recorded_events(5, stream2_uuid, 16, 6))

      {:ok, events} = Storage.read_all_streams_forward(0, 10)

      assert length(events) == 10
      assert pluck(events, :event_id) == Enum.to_list(1..10)

      {:ok, events} = Storage.read_all_streams_forward(11, 10)

      assert length(events) == 10
      assert pluck(events, :event_id) == Enum.to_list(11..20)
    end
  end

  defp create_stream(conn) do
    stream_uuid = UUID.uuid4()

    with {:ok, stream_id} <- Stream.create_stream(conn, stream_uuid) do
      {:ok, stream_uuid, stream_id}
    end
  end

  defp create_stream_containing_events(conn, event_count) do
    {:ok, stream_uuid, stream_id} = create_stream(conn)
    recorded_events = EventFactory.create_recorded_events(event_count, stream_uuid)
    {:ok, _event_ids} = Appender.append(conn, stream_id, recorded_events)

    {:ok, stream_uuid, stream_id}
  end

  defp pluck(enumerable, field), do: Enum.map(enumerable, &Map.get(&1, field))
end
