defmodule EventStore.ReadEventsTest do
  use ExUnit.Case
  doctest EventStore.Storage

  alias EventStore
  alias EventStore.EventData
  alias EventStore.EventFactory
  alias EventStore.Storage

  setup do
    {:ok, store} = Storage.start_link
    {:ok, store: store}
  end

  test "read stream forwards, when not exists"
  test "read stream forwards, when empty"

  @tag :wip
  test "read stream with single event forward", %{store: store} do
    uuid = UUID.uuid4()
    events = EventFactory.create_events(1)

    {:ok, _} = EventStore.append_to_stream(store, uuid, 0, events)
    {:ok, recorded_events} = EventStore.read_stream_forward(store, uuid, 0)

    created_event = hd(events)
    recorded_event = hd(recorded_events)

    assert recorded_event.event_id > 0
    assert recorded_event.stream_id > 0
    assert recorded_event.headers == created_event.headers
    assert recorded_event.payload == created_event.payload
  end
end
