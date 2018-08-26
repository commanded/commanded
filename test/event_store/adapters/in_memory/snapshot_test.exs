defmodule Commanded.EventStore.Adapters.InMemory.SnapshotTest do
  use Commanded.EventStore.SnapshotTestCase

  alias Commanded.EventStore.Adapters.InMemory

  setup do
    InMemory.reset!()
    :ok
  end
end
