defmodule EventStore.Storage.StreamPersistenceTest do
  use EventStore.StorageCase

  alias EventStore.EventFactory
  alias EventStore.Storage.{Appender,Stream}

  setup do
    storage_config = Application.get_env(:eventstore, EventStore.Storage)

    {:ok, conn} = Postgrex.start_link(storage_config)
    {:ok, %{conn: conn}}
  end

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

  test "stream info for an unknown stream", %{conn: conn} do
    stream_uuid = UUID.uuid4

    {:ok, nil, 0} = Stream.stream_info(conn, stream_uuid)
  end

  defp create_stream_with_events(conn, stream_uuid, number_of_events) do
    {:ok, stream_id} = Stream.create_stream(conn, stream_uuid)

    recorded_events = EventFactory.create_recorded_events(number_of_events, stream_id)

    {:ok, ^number_of_events} = Appender.append(conn, stream_id, recorded_events)

    {:ok, stream_id}
  end
end
