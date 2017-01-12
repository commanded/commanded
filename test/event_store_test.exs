defmodule EventStoreTest do
  use EventStore.StorageCase
  doctest EventStore.Storage

  alias EventStore.EventFactory
  alias EventStore.Snapshots.SnapshotData

  @all_stream "$all"
  @subscription_name "test_subscription"

  test "append single event to event store" do
    stream_uuid = UUID.uuid4
    events = EventFactory.create_events(1)

    :ok = EventStore.append_to_stream(stream_uuid, 0, events)
  end

  test "append multiple event to event store" do
    stream_uuid = UUID.uuid4
    events = EventFactory.create_events(3)

    :ok = EventStore.append_to_stream(stream_uuid, 0, events)
  end

  test "attempt to append to $all stream should fail" do
    events = EventFactory.create_events(1)

    {:error, :cannot_append_to_all_stream} = EventStore.append_to_stream(@all_stream, 0, events)
  end

  test "read stream forward from event store" do
    stream_uuid = UUID.uuid4
    events = EventFactory.create_events(1)

    :ok = EventStore.append_to_stream(stream_uuid, 0, events)
    {:ok, recorded_events} = EventStore.read_stream_forward(stream_uuid, 0)

    created_event = hd(events)
    recorded_event = hd(recorded_events)

    assert recorded_event.event_id > 0
    assert recorded_event.stream_id > 0
    assert recorded_event.data == created_event.data
    assert recorded_event.metadata == created_event.metadata
  end

  test "stream forward from event store" do
    stream_uuid = UUID.uuid4
    events = EventFactory.create_events(1)

    :ok = EventStore.append_to_stream(stream_uuid, 0, events)
    recorded_events = EventStore.stream_forward(stream_uuid) |> Enum.to_list

    created_event = hd(events)
    recorded_event = hd(recorded_events)

    assert recorded_event.event_id > 0
    assert recorded_event.stream_id > 0
    assert recorded_event.data == created_event.data
    assert recorded_event.metadata == created_event.metadata
  end

  test "stream all forward from event store" do
    stream_uuid = UUID.uuid4
    events = EventFactory.create_events(1)

    :ok = EventStore.append_to_stream(stream_uuid, 0, events)
    recorded_events = EventStore.stream_all_forward() |> Enum.to_list

    created_event = hd(events)
    recorded_event = hd(recorded_events)

    assert recorded_event.event_id > 0
    assert recorded_event.stream_id > 0
    assert recorded_event.data == created_event.data
    assert recorded_event.metadata == created_event.metadata
  end

  test "notify subscribers after event persisted" do
    stream_uuid = UUID.uuid4
    events = EventFactory.create_events(1)

    {:ok, subscription} = EventStore.subscribe_to_all_streams(@subscription_name, self())
    :ok = EventStore.append_to_stream(stream_uuid, 0, events)

    assert_receive {:events, received_events, ^subscription}

    assert length(received_events) == 1
    assert hd(received_events).data == hd(events).data
  end

  test "subscribe to all streams from current position" do
    stream_uuid = UUID.uuid4
    initial_events = EventFactory.create_events(1)
    new_events = EventFactory.create_events(1, 2)

    :ok = EventStore.append_to_stream(stream_uuid, 0, initial_events)

    {:ok, subscription} = EventStore.subscribe_to_all_streams(@subscription_name, self(), :current)

    :ok = EventStore.append_to_stream(stream_uuid, 1, new_events)

    assert_receive {:events, received_events, ^subscription}

    assert length(received_events) == 1
    assert hd(received_events).data == hd(new_events).data
  end

  defmodule ExampleData do
    defstruct [:data]
  end

  test "record snapshot" do
    assert record_snapshot() != nil
  end

  test "read a snapshot" do
    snapshot = record_snapshot()

    {:ok, read_snapshot} = EventStore.read_snapshot(snapshot.source_uuid)

    assert snapshot.source_uuid == read_snapshot.source_uuid
    assert snapshot.source_version == read_snapshot.source_version
    assert snapshot.source_type == read_snapshot.source_type
    assert snapshot.data == read_snapshot.data
  end

  test "delete a snapshot" do
    snapshot = record_snapshot()

    :ok = EventStore.delete_snapshot(snapshot.source_uuid)

    {:error, :snapshot_not_found} = EventStore.read_snapshot(snapshot.source_uuid)
  end

  defp record_snapshot do
    snapshot = %SnapshotData{
      source_uuid: UUID.uuid4,
      source_version: 1,
      source_type: Atom.to_string(ExampleData),
      data: %ExampleData{data: "some data"}
    }

    :ok = EventStore.record_snapshot(snapshot)

    snapshot
  end
end
