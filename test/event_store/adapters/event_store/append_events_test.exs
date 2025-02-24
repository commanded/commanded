defmodule Commanded.EventStore.Adapters.EventStore.AppendEventsTest do
  use Commanded.EventStore.EventStoreTestCase

  @moduletag :eventstore_adapter

  use Commanded.EventStore.AppendEventsTestCase,
    event_store: Commanded.EventStore.Adapters.EventStore
end
