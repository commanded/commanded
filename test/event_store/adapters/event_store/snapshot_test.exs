defmodule Commanded.EventStore.Adapters.EventStore.SnapshotTest do
  use Commanded.EventStore.EventStoreTestCase

  @moduletag :eventstore_adapter

  use Commanded.EventStore.SnapshotTestCase,
    event_store: Commanded.EventStore.Adapters.EventStore
end
