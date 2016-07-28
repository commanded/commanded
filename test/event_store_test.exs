defmodule EventStoreTest do
  use EventStore.StorageCase
  doctest EventStore.Storage

  alias EventStore.EventFactory

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

  test "notify subscribers after event persisted" do
    stream_uuid = UUID.uuid4
    events = EventFactory.create_events(1)

    {:ok, _subscription} = EventStore.subscribe_to_all_streams(@subscription_name, self)
    :ok = EventStore.append_to_stream(stream_uuid, 0, events)

    assert_receive {:events, received_events}

    assert length(received_events) == 1
    assert hd(received_events).data == hd(events).data
  end
end
