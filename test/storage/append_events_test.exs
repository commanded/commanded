defmodule EventStore.Storage.AppendEventsTest do
  use EventStore.StorageCase
  doctest EventStore.Storage.Appender

  alias EventStore.EventFactory
  alias EventStore.Storage.{Appender,Stream}

  setup do
    storage_config = Application.get_env(:eventstore, EventStore.Storage)

    {:ok, conn} = Postgrex.start_link(storage_config)
    {:ok, %{conn: conn}}
  end

  test "append single event to new stream", %{conn: conn} do
    {:ok, stream_id} = Stream.create_stream(conn, UUID.uuid4)
    recorded_events = EventFactory.create_recorded_events(1, stream_id)

    {:ok, 1} = Appender.append(conn, stream_id, recorded_events)
  end

  test "append multiple events to new stream", %{conn: conn} do
    {:ok, stream_id} = Stream.create_stream(conn, UUID.uuid4)
    recorded_events = EventFactory.create_recorded_events(3, stream_id)

    {:ok, 3} = Appender.append(conn, stream_id, recorded_events)
  end

  test "append single event to existing stream, in separate writes", %{conn: conn} do
    {:ok, stream_id} = Stream.create_stream(conn, UUID.uuid4)

    {:ok, 1} = Appender.append(conn, stream_id, EventFactory.create_recorded_events(1, stream_id))
    {:ok, 1} = Appender.append(conn, stream_id, EventFactory.create_recorded_events(1, stream_id, 2, 2))
  end

  test "append multiple events to existing stream, in separate writes", %{conn: conn} do
    {:ok, stream_id} = Stream.create_stream(conn, UUID.uuid4)

    {:ok, 3} = Appender.append(conn, stream_id, EventFactory.create_recorded_events(3, stream_id))
    {:ok, 3} = Appender.append(conn, stream_id, EventFactory.create_recorded_events(3, stream_id, 4, 4))
  end

  test "append events to different, new streams", %{conn: conn} do
    {:ok, stream_id1} = Stream.create_stream(conn, UUID.uuid4)
    {:ok, stream_id2} = Stream.create_stream(conn, UUID.uuid4)

    {:ok, 2} = Appender.append(conn, stream_id1, EventFactory.create_recorded_events(2, stream_id1))
    {:ok, 2} = Appender.append(conn, stream_id2, EventFactory.create_recorded_events(2, stream_id2, 3))
  end

  test "append events to different, existing streams", %{conn: conn} do
    {:ok, stream_id1} = Stream.create_stream(conn, UUID.uuid4)
    {:ok, stream_id2} = Stream.create_stream(conn, UUID.uuid4)

    {:ok, 2} = Appender.append(conn, stream_id1, EventFactory.create_recorded_events(2, stream_id1))
    {:ok, 2} = Appender.append(conn, stream_id2, EventFactory.create_recorded_events(2, stream_id2, 3))
    {:ok, 2} = Appender.append(conn, stream_id1, EventFactory.create_recorded_events(2, stream_id1, 5, 3))
    {:ok, 2} = Appender.append(conn, stream_id2, EventFactory.create_recorded_events(2, stream_id2, 7, 3))
  end

  test "append to new stream, but stream already exists", %{conn: conn} do
    {:ok, stream_id} = Stream.create_stream(conn, UUID.uuid4)
    events = EventFactory.create_recorded_events(1, stream_id)

    {:ok, 1} = Appender.append(conn, stream_id, events)
    {:error, :wrong_expected_version} = Appender.append(conn, stream_id, events)
  end

  test "append to existing stream, but stream does not exist", %{conn: conn} do
    stream_id = 1
    events = EventFactory.create_recorded_events(1, stream_id)

    {:error, :stream_not_found} = Appender.append(conn, stream_id, events)
  end

  test "append to existing stream, but wrong expected version", %{conn: conn} do
    {:ok, stream_id} = Stream.create_stream(conn, UUID.uuid4)
    events = EventFactory.create_recorded_events(2, stream_id)

    {:ok, 2} = Appender.append(conn, stream_id, events)
    {:error, :wrong_expected_version} = Appender.append(conn, stream_id, events)
  end
end
