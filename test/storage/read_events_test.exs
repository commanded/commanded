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

  # test "read stream forwards, when not exists"
  # test "read stream forwards, when empty"

  test "read stream with single event forward", %{conn: conn} do
    {:ok, _stream_uuid, stream_id} = create_stream(conn)
    {:ok, saved_events} = Appender.append(conn, stream_id, EventFactory.create_recorded_events(1, stream_id))

    {:ok, read_events} = Storage.read_stream_forward(stream_id)

    saved_event = hd(saved_events)
    read_event = hd(read_events)

    assert read_event.event_id == 1
    assert read_event.stream_id == 1
    assert read_event.headers == saved_event.headers
    assert read_event.payload == saved_event.payload
  end

  test "read all streams with multiple events forward", %{conn: conn} do
    {:ok, _stream1_uuid, stream1_id} = create_stream(conn)
    {:ok, _stream2_uuid, stream2_id} = create_stream(conn)

    {:ok, _} = Appender.append(conn, stream1_id, EventFactory.create_recorded_events(1, stream1_id))
    {:ok, _} = Appender.append(conn, stream2_id, EventFactory.create_recorded_events(1, stream2_id, 2))
    {:ok, _} = Appender.append(conn, stream1_id, EventFactory.create_recorded_events(1, stream1_id, 3, 2))
    {:ok, _} = Appender.append(conn, stream2_id, EventFactory.create_recorded_events(1, stream2_id, 4, 2))

    {:ok, events} = Storage.read_all_streams_forward

    assert length(events) == 4
    assert [1, 2, 3, 4] == Enum.map(events, &(&1.event_id))
    assert [1, 2, 1, 2] == Enum.map(events, &(&1.stream_id))
    assert [1, 1, 2, 2] == Enum.map(events, &(&1.stream_version))
  end

  test "read all streams with multiple events forward, from after last event", %{conn: conn} do
    {:ok, _stream1_uuid, stream1_id} = create_stream(conn)
    {:ok, _stream2_uuid, stream2_id} = create_stream(conn)

    {:ok, _} = Appender.append(conn, stream1_id, EventFactory.create_recorded_events(1, stream1_id))
    {:ok, _} = Appender.append(conn, stream2_id, EventFactory.create_recorded_events(1, stream2_id, 2))

    {:ok, events} = Storage.read_all_streams_forward(3)

    assert length(events) == 0
  end

  test "query latest event id when no events" do
    {:ok, latest_event_id} = Storage.latest_event_id

    assert latest_event_id == 0
  end

  test "query latest event id when events exist", %{conn: conn}do
    {:ok, _stream_uuid, stream_id} = create_stream(conn)
    {:ok, _} = Appender.append(conn, stream_id, EventFactory.create_recorded_events(3, stream_id))

    {:ok, latest_event_id} = Storage.latest_event_id

    assert latest_event_id == 3
  end

  defp create_stream(conn) do
    stream_uuid = UUID.uuid4
    {:ok, stream_id} = Stream.create_stream(conn, stream_uuid)
    {:ok, stream_uuid, stream_id}
  end
end
