defmodule Commanded.EventStore.Adapters.InMemory.SnapshotTest do
  alias Commanded.EventStore.Adapters.InMemory

  use Commanded.EventStore.InMemoryTestCase
  use Commanded.EventStore.SnapshotTestCase, event_store: InMemory
end
