defmodule EventStore.Storage.ReadEventsTest do
  use EventStore.StorageCase
  doctest EventStore.Storage

  alias EventStore.EventFactory
  alias EventStore.Storage

  # test "read stream forwards, when not exists"
  # test "read stream forwards, when empty"

  test "read stream with single event forward", %{storage: storage} do
    uuid = UUID.uuid4()
    events = EventFactory.create_events(1)

    {:ok, _} = Storage.append_to_stream(storage, uuid, 0, events)
    {:ok, recorded_events} = Storage.read_stream_forward(storage, uuid, 0)

    created_event = hd(events)
    recorded_event = hd(recorded_events)

    assert recorded_event.event_id > 0
    assert recorded_event.stream_id > 0
    assert recorded_event.headers == created_event.headers
    assert recorded_event.payload == created_event.payload
  end
end
