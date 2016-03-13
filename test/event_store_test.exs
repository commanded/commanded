defmodule EventStoreTest do
  use ExUnit.Case
  doctest EventStore.Storage

  alias EventStore.EventFactory

  @subscription_name "test_subscription"

  setup do
    {:ok, store} = EventStore.start_link
    {:ok, store: store}
  end

  test "append single event to event store", %{store: store} do
    stream_uuid = UUID.uuid4()
    events = EventFactory.create_events(1)

    {:ok, _persisted_events} = EventStore.append_to_stream(store, stream_uuid, 0, events)
  end

  test "attempt to append to $all stream should fail", %{store: store} do
    events = EventFactory.create_events(1)

    {:error, :cannot_append_to_all_stream} = EventStore.append_to_stream(store, "$all", 0, events)
  end

  test "read stream forward from event store", %{store: store} do
    stream_uuid = UUID.uuid4()
    events = EventFactory.create_events(1)

    {:ok, _} = EventStore.append_to_stream(store, stream_uuid, 0, events)
    {:ok, recorded_events} = EventStore.read_stream_forward(store, stream_uuid, 0)

    created_event = hd(events)
    recorded_event = hd(recorded_events)

    assert recorded_event.event_id > 0
    assert recorded_event.stream_id > 0
    assert recorded_event.headers == created_event.headers
    assert recorded_event.payload == created_event.payload
  end

  test "notify subscribers after event persisted", %{store: store} do
    stream_uuid = UUID.uuid4()
    events = EventFactory.create_events(1)

    {:ok, _} = EventStore.subscribe_to_all_streams(store, @subscription_name, self)
    {:ok, _} = EventStore.append_to_stream(store, stream_uuid, 0, events)

    assert_receive {:events, events}

    assert length(events) == 1
  end
end
