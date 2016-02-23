defmodule EventStore.StorageTest do
  use ExUnit.Case
  doctest EventStore.Storage

  alias EventStore.Storage

  setup do
    {:ok, store} = Storage.start_link
    {:ok, store: store}
  end

  test "initialise store", %{store: store} do
    Storage.initialize_store!(store)
  end

  test "append to new stream", %{store: store} do
    uuid = UUID.uuid4()

    {:ok, stream_id} = Storage.append_to_stream(store, uuid, 0, %{key: "value"})
    assert is_number(stream_id)
  end

  test "append to new stream but stream already exists", %{store: store} do
    uuid = UUID.uuid4()

    {:ok, stream_id} = Storage.append_to_stream(store, uuid, 0, %{key: "value"})
    {:error, :wrong_expected_version} = Storage.append_to_stream(store, uuid, 0, %{key: "value"})
  end
end
