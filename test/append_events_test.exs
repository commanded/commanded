defmodule EventStore.AppendEventsTest do
  use ExUnit.Case
  doctest EventStore.Storage

  alias EventStore
  alias EventStore.EventFactory
  alias EventStore.Storage

  setup do
    {:ok, store} = Storage.start_link
    {:ok, store: store}
  end

  test "initialise store", %{store: store} do
    Storage.initialize_store!(store)
  end

  test "append single event to new stream", %{store: store} do
    uuid = UUID.uuid4()
    events = EventFactory.create_events(1)

    {:ok, _} = EventStore.append_to_stream(store, uuid, 0, events)
  end

  test "append multiple events to new stream", %{store: store} do
    uuid = UUID.uuid4()
    events = EventFactory.create_events(3)

    {:ok, _} = EventStore.append_to_stream(store, uuid, 0, events)
  end

  test "append single event to existing stream", %{store: store} do
    uuid = UUID.uuid4()

    {:ok, 1} = EventStore.append_to_stream(store, uuid, 0, EventFactory.create_events(1))
    {:ok, 1} = EventStore.append_to_stream(store, uuid, 1, EventFactory.create_events(1))
  end

  test "append multiple events to existing stream", %{store: store} do
    uuid = UUID.uuid4()

    {:ok, 3} = EventStore.append_to_stream(store, uuid, 0, EventFactory.create_events(3))
    {:ok, 3} = EventStore.append_to_stream(store, uuid, 3, EventFactory.create_events(3))
  end

  test "append events to different, new streams", %{store: store} do
    {:ok, 2} = EventStore.append_to_stream(store, UUID.uuid4(), 0, EventFactory.create_events(2))
    {:ok, 2} = EventStore.append_to_stream(store, UUID.uuid4(), 0, EventFactory.create_events(2))
  end

  test "append events to different, existing streams", %{store: store} do
    stream1_uuid = UUID.uuid4()
    stream2_uuid = UUID.uuid4()

    {:ok, 2} = EventStore.append_to_stream(store, stream1_uuid, 0, EventFactory.create_events(2))
    {:ok, 2} = EventStore.append_to_stream(store, stream2_uuid, 0, EventFactory.create_events(2))
    {:ok, 2} = EventStore.append_to_stream(store, stream1_uuid, 2, EventFactory.create_events(2))
    {:ok, 2} = EventStore.append_to_stream(store, stream2_uuid, 2, EventFactory.create_events(2))
  end

  test "append to new stream, but stream already exists", %{store: store} do
    uuid = UUID.uuid4()
    events = EventFactory.create_events(1)

    {:ok, 1} = EventStore.append_to_stream(store, uuid, 0, events)
    {:error, :wrong_expected_version} = EventStore.append_to_stream(store, uuid, 0, events)
  end

  test "append to existing stream, but stream does not exist", %{store: store} do
    uuid = UUID.uuid4()
    events = EventFactory.create_events(1)

    {:error, :stream_not_found} = EventStore.append_to_stream(store, uuid, 1, events)
  end

  test "append to existing stream, but wrong expected version", %{store: store} do
    uuid = UUID.uuid4()
    events = EventFactory.create_events(2)

    {:ok, _} = EventStore.append_to_stream(store, uuid, 0, events)
    {:error, :wrong_expected_version} = EventStore.append_to_stream(store, uuid, 1, events)
  end
end
