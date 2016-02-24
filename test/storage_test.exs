defmodule EventStore.StorageTest do
  use ExUnit.Case
  doctest EventStore.Storage

  alias EventStore.Storage
  alias EventStore.EventData

  setup do
    {:ok, store} = Storage.start_link
    Storage.initialize_store!(store)
    {:ok, store: store}
  end

  test "initialise store", %{store: store} do
    Storage.initialize_store!(store)
  end

  test "append single event to new stream", %{store: store} do
    uuid = UUID.uuid4()
    events = create_events

    {:ok, _} = Storage.append_to_stream(store, uuid, 0, events)
  end

  test "append multiple events to new stream", %{store: store} do
    uuid = UUID.uuid4()
    events = create_events(3)

    {:ok, _} = Storage.append_to_stream(store, uuid, 0, events)
  end

  test "append single event to existing stream"
  test "append multiple events to existing stream"

  test "append to new stream, but stream already exists", %{store: store} do
    uuid = UUID.uuid4()
    events = create_events

    {:ok, 1} = Storage.append_to_stream(store, uuid, 0, events)
    {:error, :wrong_expected_version} = Storage.append_to_stream(store, uuid, 0, events)
  end

  test "append to existing stream, but stream does not exist", %{store: store} do
    uuid = UUID.uuid4()
    events = create_events

    {:error, :stream_not_found} = Storage.append_to_stream(store, uuid, 1, events)
  end

  @tag :wip  
  test "append to existing stream, but wrong expected version", %{store: store} do
    uuid = UUID.uuid4()
    events = create_events(2)

    {:ok, _} = Storage.append_to_stream(store, uuid, 0, events)
    {:error, :wrong_expected_version} = Storage.append_to_stream(store, uuid, 1, events)
  end

  defp create_events(number_of_events \\ 1) do
    correlation_id = UUID.uuid4()

    1..number_of_events
    |> Enum.map(fn number -> 
      %EventData{
        event_type: "EventStore.StorageTest.ExampleEvent",
        correlation_id: correlation_id,
        headers: %{user: "user@example.com"},
        payload: %{event: number}
      }
    end)
  end
end
