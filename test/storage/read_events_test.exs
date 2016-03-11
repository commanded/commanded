defmodule EventStore.Storage.ReadEventsTest do
  use EventStore.StorageCase
  doctest EventStore.Storage

  alias EventStore.EventFactory
  alias EventStore.Storage

  # test "read stream forwards, when not exists"
  # test "read stream forwards, when empty"

  test "read stream with single event forward", %{storage: storage} do
    stream_uuid = UUID.uuid4()
    events = EventFactory.create_events(1)

    {:ok, _} = Storage.append_to_stream(storage, stream_uuid, 0, events)
    {:ok, recorded_events} = Storage.read_stream_forward(storage, stream_uuid, 0)

    created_event = hd(events)
    recorded_event = hd(recorded_events)

    assert recorded_event.event_id == 1
    assert recorded_event.stream_id == 1
    assert recorded_event.headers == created_event.headers
    assert recorded_event.payload == created_event.payload
  end

  test "read all streams with multiple events forward", %{storage: storage} do
    stream1_uuid = UUID.uuid4()
    stream2_uuid = UUID.uuid4()

    {:ok, _} = Storage.append_to_stream(storage, stream1_uuid, 0, EventFactory.create_events(1))
    {:ok, _} = Storage.append_to_stream(storage, stream2_uuid, 0, EventFactory.create_events(1))
    {:ok, _} = Storage.append_to_stream(storage, stream1_uuid, 1, EventFactory.create_events(1))
    {:ok, _} = Storage.append_to_stream(storage, stream2_uuid, 1, EventFactory.create_events(1))

    {:ok, events} = Storage.read_all_streams_forward(storage, 0)

    assert length(events) == 4
    assert [1, 2, 3, 4] == Enum.map(events, &(&1.event_id))
    assert [1, 2, 1, 2] == Enum.map(events, &(&1.stream_id))
    assert [1, 1, 2, 2] == Enum.map(events, &(&1.stream_version))
  end

  test "read all streams with multiple events forward, from after last event", %{storage: storage} do
    stream1_uuid = UUID.uuid4()
    stream2_uuid = UUID.uuid4()

    {:ok, _} = Storage.append_to_stream(storage, stream1_uuid, 0, EventFactory.create_events(1))
    {:ok, _} = Storage.append_to_stream(storage, stream2_uuid, 0, EventFactory.create_events(1))

    {:ok, events} = Storage.read_all_streams_forward(storage, 3)

    assert length(events) == 0
  end

  test "query latest event id when no events", %{storage: storage} do
    {:ok, latest_event_id} = Storage.latest_event_id(storage)

    assert latest_event_id == 0
  end

  test "query latest event id when events", %{storage: storage} do
    stream_uuid = UUID.uuid4()
    events = EventFactory.create_events(3)

    {:ok, _} = Storage.append_to_stream(storage, stream_uuid, 0, events)

    {:ok, latest_event_id} = Storage.latest_event_id(storage)

    assert latest_event_id == 3
  end
end
