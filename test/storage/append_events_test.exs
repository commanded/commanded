defmodule EventStore.Storage.AppendEventsTest do
  use EventStore.StorageCase
  doctest EventStore.Storage.Appender

  alias EventStore.EventFactory
  alias EventStore.Storage.{Appender,Stream}

  test "append single event to new stream", %{conn: conn} do
    {:ok, stream_id} = Stream.create_stream(conn, UUID.uuid4)
    recorded_events = EventFactory.create_recorded_events(1, stream_id)

    {:ok, [1]} = Appender.append(conn, recorded_events)
  end

  test "append multiple events to new stream", %{conn: conn} do
    {:ok, stream_id} = Stream.create_stream(conn, UUID.uuid4)
    recorded_events = EventFactory.create_recorded_events(3, stream_id)

    {:ok, [1, 2, 3]} = Appender.append(conn, recorded_events)
  end

  test "append single event to existing stream, in separate writes", %{conn: conn} do
    {:ok, stream_id} = Stream.create_stream(conn, UUID.uuid4)

    {:ok, [1]} = Appender.append(conn, EventFactory.create_recorded_events(1, stream_id))
    {:ok, [2]} = Appender.append(conn, EventFactory.create_recorded_events(1, stream_id, 2, 2))
  end

  test "append multiple events to existing stream, in separate writes", %{conn: conn} do
    {:ok, stream_id} = Stream.create_stream(conn, UUID.uuid4)

    {:ok, [1, 2, 3]} = Appender.append(conn, EventFactory.create_recorded_events(3, stream_id))
    {:ok, [4, 5, 6]} = Appender.append(conn, EventFactory.create_recorded_events(3, stream_id, 4, 4))
  end

  test "append events to different, new streams", %{conn: conn} do
    {:ok, stream_id1} = Stream.create_stream(conn, UUID.uuid4)
    {:ok, stream_id2} = Stream.create_stream(conn, UUID.uuid4)

    {:ok, [1, 2]} = Appender.append(conn, EventFactory.create_recorded_events(2, stream_id1))
    {:ok, [3, 4]} = Appender.append(conn, EventFactory.create_recorded_events(2, stream_id2, 3))
  end

  test "append events to different, existing streams", %{conn: conn} do
    {:ok, stream_id1} = Stream.create_stream(conn, UUID.uuid4)
    {:ok, stream_id2} = Stream.create_stream(conn, UUID.uuid4)

    {:ok, [1, 2]} = Appender.append(conn, EventFactory.create_recorded_events(2, stream_id1))
    {:ok, [3, 4]} = Appender.append(conn, EventFactory.create_recorded_events(2, stream_id2, 3))
    {:ok, [5, 6]} = Appender.append(conn, EventFactory.create_recorded_events(2, stream_id1, 5, 3))
    {:ok, [7, 8]} = Appender.append(conn, EventFactory.create_recorded_events(2, stream_id2, 7, 3))
  end

  test "append to new stream, but stream already exists", %{conn: conn} do
    {:ok, stream_id} = Stream.create_stream(conn, UUID.uuid4)
    events = EventFactory.create_recorded_events(1, stream_id)

    {:ok, [1]} = Appender.append(conn, events)
    {:error, :wrong_expected_version} = Appender.append(conn, events)
  end

  test "append to existing stream, but stream does not exist", %{conn: conn} do
    stream_id = 1
    events = EventFactory.create_recorded_events(1, stream_id)

    {:error, :stream_not_found} = Appender.append(conn, events)
  end

  test "append to existing stream, but wrong expected version", %{conn: conn} do
    {:ok, stream_id} = Stream.create_stream(conn, UUID.uuid4)
    events = EventFactory.create_recorded_events(2, stream_id)

    {:ok, [1, 2]} = Appender.append(conn, events)
    {:error, :wrong_expected_version} = Appender.append(conn, events)
  end
end
