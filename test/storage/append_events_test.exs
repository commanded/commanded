defmodule EventStore.Storage.AppendEventsTest do
  use EventStore.StorageCase
  doctest EventStore.Storage.Appender

  alias EventStore.EventFactory
  alias EventStore.Storage.Appender

  setup do
    storage_config = Application.get_env(:eventstore, EventStore.Storage)

    {:ok, conn} = Postgrex.start_link(storage_config)
    {:ok, %{conn: conn}}
  end

  test "append single event to new stream", %{conn: conn} do
    stream_id = 1
    recorded_events = EventFactory.create_recorded_events(1, stream_id)

    {:ok, persisted_events} = Appender.append(conn, stream_id, recorded_events)

    assert length(persisted_events) == 1
    assert hd(persisted_events).event_id == 1
  end

  test "append multiple events to new stream", %{conn: conn} do
    stream_id = 1
    recorded_events = EventFactory.create_recorded_events(3, stream_id)

    {:ok, persisted_events} = Appender.append(conn, stream_id, recorded_events)
    assert length(persisted_events) == 3
  end

  test "append single event to existing stream, in separate writes", %{conn: conn} do
    stream_id = 1

    {:ok, persisted_events} = Appender.append(conn, stream_id, EventFactory.create_recorded_events(1, stream_id))
    assert length(persisted_events) == 1

    {:ok, persisted_events} = Appender.append(conn, stream_id, EventFactory.create_recorded_events(1, stream_id, 2, 2))
    assert length(persisted_events) == 1
  end

  test "append multiple events to existing stream, in separate writes", %{conn: conn} do
    stream_id = 1

    {:ok, persisted_events} = Appender.append(conn, stream_id, EventFactory.create_recorded_events(3, stream_id))
    assert length(persisted_events) == 3

    {:ok, persisted_events} = Appender.append(conn, stream_id, EventFactory.create_recorded_events(3, stream_id, 4, 4))
    assert length(persisted_events) == 3
  end

  test "append events to different, new streams", %{conn: conn} do
    stream_id1 = 1
    stream_id2 = 2

    {:ok, persisted_events} = Appender.append(conn, stream_id1, EventFactory.create_recorded_events(2, stream_id1))
    assert length(persisted_events) == 2

    {:ok, persisted_events} = Appender.append(conn, stream_id2, EventFactory.create_recorded_events(2, stream_id2, 3))
    assert length(persisted_events) == 2
  end

  test "append events to different, existing streams", %{conn: conn} do
    stream_id1 = 1
    stream_id2 = 2

    {:ok, _} = Appender.append(conn, stream_id1, EventFactory.create_recorded_events(2, stream_id1))
    {:ok, _} = Appender.append(conn, stream_id2, EventFactory.create_recorded_events(2, stream_id2, 3))
    {:ok, _} = Appender.append(conn, stream_id1, EventFactory.create_recorded_events(2, stream_id1, 5, 3))
    {:ok, _} = Appender.append(conn, stream_id2, EventFactory.create_recorded_events(2, stream_id2, 7, 3))
  end

  test "append to new stream, but stream already exists", %{conn: conn} do
    stream_id = 1
    events = EventFactory.create_recorded_events(1, stream_id)

    {:ok, _} = Appender.append(conn, stream_id, events)
    {:error, :wrong_expected_version} = Appender.append(conn, stream_id, events)
  end

  @tag :wip
  test "append to existing stream, but stream does not exist", %{conn: conn} do
    stream_id = 1
    events = EventFactory.create_recorded_events(1, stream_id)

    {:error, :stream_not_found} = Appender.append(conn, stream_id, events)
  end

  test "append to existing stream, but wrong expected version", %{conn: conn} do
    stream_id = 1
    events = EventFactory.create_recorded_events(2, stream_id)

    {:ok, _} = Appender.append(conn, stream_id, events)
    {:error, :wrong_expected_version} = Appender.append(conn, stream_id, events)
  end
end
