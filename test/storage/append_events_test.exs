defmodule EventStore.Storage.AppendEventsTest do
  use EventStore.StorageCase
  doctest EventStore.Storage.Appender

  alias EventStore.EventFactory
  alias EventStore.Storage.{Appender,Stream}

  test "append single event to new stream", %{conn: conn} do
    {:ok, stream_uuid, stream_id} = create_stream(conn)
    recorded_events = EventFactory.create_recorded_events(1, stream_uuid)

    {:ok, [1]} = Appender.append(conn, stream_id, recorded_events)
  end

  test "append multiple events to new stream", %{conn: conn} do
    {:ok, stream_uuid, stream_id} = create_stream(conn)
    recorded_events = EventFactory.create_recorded_events(3, stream_uuid)

    {:ok, [1, 2, 3]} = Appender.append(conn, stream_id, recorded_events)
  end

  test "append single event to existing stream, in separate writes", %{conn: conn} do
    {:ok, stream_uuid, stream_id} = create_stream(conn)

    {:ok, [1]} = Appender.append(conn, stream_id, EventFactory.create_recorded_events(1, stream_uuid))
    {:ok, [2]} = Appender.append(conn, stream_id, EventFactory.create_recorded_events(1, stream_uuid, 2, 2))
  end

  test "append multiple events to existing stream, in separate writes", %{conn: conn} do
    {:ok, stream_uuid, stream_id} = create_stream(conn)

    {:ok, [1, 2, 3]} = Appender.append(conn, stream_id, EventFactory.create_recorded_events(3, stream_uuid))
    {:ok, [4, 5, 6]} = Appender.append(conn, stream_id, EventFactory.create_recorded_events(3, stream_uuid, 4, 4))
  end

  test "append events to different, new streams", %{conn: conn} do
    {:ok, stream1_uuid, stream1_id} = create_stream(conn)
    {:ok, stream2_uuid, stream2_id} = create_stream(conn)

    {:ok, [1, 2]} = Appender.append(conn, stream1_id, EventFactory.create_recorded_events(2, stream1_uuid))
    {:ok, [3, 4]} = Appender.append(conn, stream2_id, EventFactory.create_recorded_events(2, stream2_uuid, 3))
  end

  test "append events to different, existing streams", %{conn: conn} do
    {:ok, stream1_uuid, stream1_id} = create_stream(conn)
    {:ok, stream2_uuid, stream2_id} = create_stream(conn)

    {:ok, [1, 2]} = Appender.append(conn, stream1_id, EventFactory.create_recorded_events(2, stream1_uuid))
    {:ok, [3, 4]} = Appender.append(conn, stream2_id, EventFactory.create_recorded_events(2, stream2_uuid, 3))
    {:ok, [5, 6]} = Appender.append(conn, stream1_id, EventFactory.create_recorded_events(2, stream1_uuid, 5, 3))
    {:ok, [7, 8]} = Appender.append(conn, stream2_id, EventFactory.create_recorded_events(2, stream2_uuid, 7, 3))
  end

  test "append to new stream, but stream already exists", %{conn: conn} do
    {:ok, stream_uuid, stream_id} = create_stream(conn)
    events = EventFactory.create_recorded_events(1, stream_uuid)

    {:ok, [1]} = Appender.append(conn, stream_id, events)
    {:error, :wrong_expected_version} = Appender.append(conn, stream_id, events)
  end

  test "append to existing stream, but stream does not exist", %{conn: conn} do
    stream_uuid = UUID.uuid4()
    stream_id = 1
    events = EventFactory.create_recorded_events(1, stream_uuid)

    {:error, :stream_not_found} = Appender.append(conn, stream_id, events)
  end

  test "append to existing stream, but wrong expected version", %{conn: conn} do
    {:ok, stream_uuid, stream_id} = create_stream(conn)
    events = EventFactory.create_recorded_events(2, stream_uuid)

    {:ok, [1, 2]} = Appender.append(conn, stream_id, events)
    {:error, :wrong_expected_version} = Appender.append(conn, stream_id, events)
  end

  defp create_stream(conn) do
    stream_uuid = UUID.uuid4()
    {:ok, stream_id} = Stream.create_stream(conn, stream_uuid)

    {:ok, stream_uuid, stream_id}
  end
end
