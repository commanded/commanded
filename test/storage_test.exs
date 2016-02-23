defmodule EventStore.StorageTest do
  use ExUnit.Case
  doctest EventStore.Storage

  alias EventStore.Storage

  setup do
    {:ok, store} = Storage.start_link
    Storage.initialize_store!(store)
    {:ok, store: store}
  end

  test "initialise store", %{store: store} do
    Storage.initialize_store!(store)
  end

  @tag :wip
  test "append to new stream", %{store: store} do
    uuid = UUID.uuid4()
    events = [%{key: "value"}]

    {:ok, 1} = Storage.append_to_stream(store, uuid, 0, events)
  end

  test "append to new stream, but stream already exists", %{store: store} do
    uuid = UUID.uuid4()
    events = [%{key: "value"}]

    {:ok, 1} = Storage.append_to_stream(store, uuid, 0, events)
    {:error, :wrong_expected_version} = Storage.append_to_stream(store, uuid, 0, events)
  end

  test "append to existing stream, but stream does not exist", %{store: store} do
    uuid = UUID.uuid4()

    {:error, :stream_not_found} = Storage.append_to_stream(store, uuid, 1, %{key: "value"})
  end
end
