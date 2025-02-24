defmodule Commanded.EventStore.Adapters.EventStore.SubscriptionTest do
  use Commanded.EventStore.EventStoreTestCase

  @moduletag :eventstore_adapter

  use Commanded.EventStore.SubscriptionTestCase,
    event_store: Commanded.EventStore.Adapters.EventStore
end
