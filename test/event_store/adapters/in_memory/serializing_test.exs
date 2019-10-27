defmodule Commanded.EventStore.Adapters.InMemory.SerializingTest do
  use Commanded.EventStore.SerializationCase,
    adapter: Commanded.EventStore.Adapters.InMemory
end
