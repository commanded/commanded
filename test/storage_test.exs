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
end
