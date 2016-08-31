defmodule EventStore.Storage.SnapshotTest do
  use EventStore.StorageCase

  alias EventStore.EventFactory
  alias EventStore.Storage.Snapshot

  setup do
    storage_config = Application.get_env(:eventstore, EventStore.Storage)

    {:ok, conn} = Postgrex.start_link(storage_config)
    {:ok, %{conn: conn}}
  end

  test "read snapshot when not exists", %{conn: conn} do
    source_uuid = UUID.uuid4
    {:error, :snapshot_not_found} = Snapshot.read_snapshot(conn, source_uuid)
  end

  test "read snapshot when present", %{conn: conn} do
    source_uuid = UUID.uuid4
    source_version = 1
    recorded_event = hd(EventFactory.create_recorded_events(1, 1))
    :ok = Snapshot.record_snapshot(conn, source_uuid, source_version, recorded_event.data, recorded_event.metadata)

    {:ok, snapshot} = Snapshot.read_snapshot(conn, source_uuid)

    assert snapshot.source_uuid == source_uuid
    assert snapshot.source_version == source_version
    assert snapshot.data == recorded_event.data
    assert snapshot.metadata == recorded_event.metadata
  end

  test "record snapshot when none exists", %{conn: conn} do
    source_uuid = UUID.uuid4
    source_version = 1
    recorded_event = hd(EventFactory.create_recorded_events(1, 1))

    :ok = Snapshot.record_snapshot(conn, source_uuid, source_version, recorded_event.data, recorded_event.metadata)
  end

  test "record snapshot when present should update existing", %{conn: conn} do
    source_uuid = UUID.uuid4
    initial_recorded_event = hd(EventFactory.create_recorded_events(1, 1))
    updated_recorded_event = hd(EventFactory.create_recorded_events(1, 1, 2))

    :ok = Snapshot.record_snapshot(conn, source_uuid, 1, initial_recorded_event.data, initial_recorded_event.metadata)
    :ok = Snapshot.record_snapshot(conn, source_uuid, 2, updated_recorded_event.data, updated_recorded_event.metadata)

    {:ok, snapshot} = Snapshot.read_snapshot(conn, source_uuid)
    assert snapshot.source_uuid == source_uuid
    assert snapshot.source_version == 2
    assert snapshot.data == updated_recorded_event.data
    assert snapshot.metadata == updated_recorded_event.metadata
  end
end
