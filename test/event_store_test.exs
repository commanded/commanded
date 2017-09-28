defmodule EventStoreTest do
  use EventStore.StorageCase
  doctest EventStore.Storage

  alias EventStore.EventFactory
  alias EventStore.Snapshots.SnapshotData

  @all_stream "$all"
  @subscription_name "test_subscription"

  test "append single event to event store" do
    stream_uuid = UUID.uuid4()
    events = EventFactory.create_events(1)

    :ok = EventStore.append_to_stream(stream_uuid, 0, events)
  end

  test "append multiple event to event store" do
    stream_uuid = UUID.uuid4()
    events = EventFactory.create_events(3)

    :ok = EventStore.append_to_stream(stream_uuid, 0, events)
  end

  test "attempt to append to `$all` stream should fail" do
    events = EventFactory.create_events(1)

    {:error, :cannot_append_to_all_stream} = EventStore.append_to_stream(@all_stream, 0, events)
  end

  test "read stream forward from event store" do
    stream_uuid = UUID.uuid4()
    events = EventFactory.create_events(1)

    :ok = EventStore.append_to_stream(stream_uuid, 0, events)
    {:ok, recorded_events} = EventStore.read_stream_forward(stream_uuid, 0)

    created_event = hd(events)
    recorded_event = hd(recorded_events)

    assert is_integer(recorded_event.event_id)
    assert recorded_event.event_id > 0
    assert recorded_event.stream_uuid == stream_uuid
    assert recorded_event.data == created_event.data
    assert recorded_event.metadata == created_event.metadata
  end

  test "stream forward from event store" do
    stream_uuid = UUID.uuid4()
    events = EventFactory.create_events(1)

    :ok = EventStore.append_to_stream(stream_uuid, 0, events)
    recorded_events = EventStore.stream_forward(stream_uuid) |> Enum.to_list

    created_event = hd(events)
    recorded_event = hd(recorded_events)

    assert recorded_event.event_id > 0
    assert recorded_event.stream_uuid == stream_uuid
    assert recorded_event.data == created_event.data
    assert recorded_event.metadata == created_event.metadata
  end

  test "stream all forward from event store" do
    stream_uuid = UUID.uuid4()
    events = EventFactory.create_events(1)

    :ok = EventStore.append_to_stream(stream_uuid, 0, events)
    recorded_events = EventStore.stream_all_forward() |> Enum.to_list

    created_event = hd(events)
    recorded_event = hd(recorded_events)

    assert recorded_event.event_id > 0
    assert recorded_event.stream_uuid == stream_uuid
    assert recorded_event.data == created_event.data
    assert recorded_event.metadata == created_event.metadata
  end

  test "notify subscribers after event persisted" do
    stream_uuid = UUID.uuid4()
    events = EventFactory.create_events(1)

    {:ok, _subscription} = EventStore.subscribe_to_all_streams(@subscription_name, self())
    :ok = EventStore.append_to_stream(stream_uuid, 0, events)

    assert_receive {:events, received_events}

    assert length(received_events) == 1
    assert hd(received_events).data == hd(events).data

    :ok = EventStore.unsubscribe_from_all_streams(@subscription_name)
  end

  test "subscribe to all streams from current position" do
    stream_uuid = UUID.uuid4()
    initial_events = EventFactory.create_events(1)
    new_events = EventFactory.create_events(1, 2)

    :ok = EventStore.append_to_stream(stream_uuid, 0, initial_events)

    {:ok, _subscription} = EventStore.subscribe_to_all_streams(@subscription_name, self(), start_from: :current)

    :ok = EventStore.append_to_stream(stream_uuid, 1, new_events)

    assert_receive {:events, received_events}

    assert length(received_events) == 1
    assert hd(received_events).data == hd(new_events).data

    :ok = EventStore.unsubscribe_from_all_streams(@subscription_name)
  end

  test "catch-up subscription should receive all persisted events" do
    stream_uuid = UUID.uuid4()
    events = EventFactory.create_events(3)
    :ok = EventStore.append_to_stream(stream_uuid, 0, events)

    {:ok, subscription} = EventStore.subscribe_to_all_streams(@subscription_name, self())

    # should receive events appended before subscription created
    assert_receive {:events, received_events}
    EventStore.ack(subscription, received_events)

    assert length(received_events) == 3
    assert pluck(received_events, :event_id) == [1, 2, 3]
    assert pluck(received_events, :stream_uuid) == [stream_uuid, stream_uuid, stream_uuid]
    assert pluck(received_events, :stream_version) == [1, 2, 3]
    assert pluck(received_events, :correlation_id) == pluck(events, :correlation_id)
    assert pluck(received_events, :causation_id) == pluck(events, :causation_id)
    assert pluck(received_events, :event_type) == pluck(events, :event_type)
    assert pluck(received_events, :data) == pluck(events, :data)
    assert pluck(received_events, :metadata) == pluck(events, :metadata)
    refute pluck(received_events, :created_at) |> Enum.any?(&is_nil/1)

    new_events = EventFactory.create_events(3, 4)
    :ok = EventStore.append_to_stream(stream_uuid, 3, new_events)

    # should receive events appended after subscription created
    assert_receive {:events, received_events}
    EventStore.ack(subscription, received_events)

    assert length(received_events) == 3
    assert pluck(received_events, :event_id) == [4, 5, 6]
    assert pluck(received_events, :stream_uuid) == [stream_uuid, stream_uuid, stream_uuid]
    assert pluck(received_events, :stream_version) == [4, 5, 6]
    assert pluck(received_events, :correlation_id) == pluck(new_events, :correlation_id)
    assert pluck(received_events, :causation_id) == pluck(new_events, :causation_id)
    assert pluck(received_events, :event_type) == pluck(new_events, :event_type)
    assert pluck(received_events, :data) == pluck(new_events, :data)
    assert pluck(received_events, :metadata) == pluck(new_events, :metadata)
    refute pluck(received_events, :created_at) |> Enum.any?(&is_nil/1)

    :ok = EventStore.unsubscribe_from_all_streams(@subscription_name)
  end

  defmodule ExampleData, do: defstruct [:data]

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

    assert {:error, :snapshot_not_found} == EventStore.read_snapshot(snapshot.source_uuid)
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

  defp pluck(enumerable, field), do: Enum.map(enumerable, &Map.get(&1, field))
end
