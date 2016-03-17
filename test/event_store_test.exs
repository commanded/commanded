defmodule EventStoreTest do
  use EventStore.StorageCase
  doctest EventStore.Storage

  alias EventStore.EventFactory

  @subscription_name "test_subscription"

  test "append single event to event store" do
    stream_uuid = UUID.uuid4()
    events = EventFactory.create_events(1)

    {:ok, persisted_events} = EventStore.append_to_stream(stream_uuid, 0, events)

    assert length(persisted_events) == 1
  end

  test "attempt to append to $all stream should fail" do
    events = EventFactory.create_events(1)

    {:error, :cannot_append_to_all_stream} = EventStore.append_to_stream("$all", 0, events)
  end

  test "read stream forward from event store" do
    stream_uuid = UUID.uuid4()
    events = EventFactory.create_events(1)

    {:ok, _} = EventStore.append_to_stream(stream_uuid, 0, events)
    {:ok, recorded_events} = EventStore.read_stream_forward(stream_uuid, 0)

    created_event = hd(events)
    recorded_event = hd(recorded_events)

    assert recorded_event.event_id > 0
    assert recorded_event.stream_id > 0
    assert recorded_event.headers == created_event.headers
    assert recorded_event.payload == created_event.payload
  end

  test "notify subscribers after event persisted" do
    stream_uuid = UUID.uuid4()
    events = EventFactory.create_events(1)

    {:ok, _} = EventStore.subscribe_to_all_streams(@subscription_name, self)
    {:ok, persisted_events} = EventStore.append_to_stream(stream_uuid, 0, events)

    assert_receive {:events, received_events}

    assert length(received_events) == 1
    assert received_events == persisted_events
  end
end
