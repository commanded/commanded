defmodule EventStore.Storage.StreamPersistenceTest do
  use EventStore.StorageCase

  alias EventStore.EventFactory
  alias EventStore.Storage.{Appender,Stream}

  test "create stream", %{conn: conn} do
    stream_uuid = UUID.uuid4

    {:ok, _stream_id} = Stream.create_stream(conn, stream_uuid)
  end

  test "create stream when already exists", %{conn: conn} do
    stream_uuid = UUID.uuid4

    {:ok, _stream_id} = Stream.create_stream(conn, stream_uuid)
    {:error, :stream_exists} = Stream.create_stream(conn, stream_uuid)
  end

  test "stream info for stream with no events", %{conn: conn} do
    stream_uuid = UUID.uuid4

    {:ok, stream_id} = Stream.create_stream(conn, stream_uuid)
    {:ok, ^stream_id, 0} = Stream.stream_info(conn, stream_uuid)
  end

  test "stream info for stream with one event", %{conn: conn} do
    stream_uuid = UUID.uuid4

    {:ok, stream_id} = create_stream_with_events(conn, stream_uuid, 1)

    {:ok, ^stream_id, 1} = Stream.stream_info(conn, stream_uuid)
  end

  test "stream info for stream with some events", %{conn: conn} do
    stream_uuid = UUID.uuid4
    {:ok, stream_id} = create_stream_with_events(conn, stream_uuid, 3)

    {:ok, ^stream_id, 3} = Stream.stream_info(conn, stream_uuid)
  end

  test "stream info for additional stream with some events", %{conn: conn} do
    first_stream_uuid = UUID.uuid4
    second_stream_uuid = UUID.uuid4

    {:ok, first_stream_id} = create_stream_with_events(conn, first_stream_uuid, 3)
    {:ok, second_stream_id} = create_stream_with_events(conn, second_stream_uuid, 2, 4)

    {:ok, ^first_stream_id, 3} = Stream.stream_info(conn, first_stream_uuid)
    {:ok, ^second_stream_id, 2} = Stream.stream_info(conn, second_stream_uuid)
  end

  test "stream info for an unknown stream", %{conn: conn} do
    stream_uuid = UUID.uuid4

    {:ok, nil, 0} = Stream.stream_info(conn, stream_uuid)
  end

  defp create_stream_with_events(conn, stream_uuid, number_of_events, initial_event_id \\ 1) do
    {:ok, stream_id} = Stream.create_stream(conn, stream_uuid)

    recorded_events = EventFactory.create_recorded_events(number_of_events, stream_id, initial_event_id)
    expected_event_ids = Enum.map(recorded_events, fn event -> event.event_id end)

    {:ok, ^expected_event_ids} = Appender.append(conn, recorded_events)

    {:ok, stream_id}
  end
end
