defmodule Commanded.EventStore.Adapters.InMemory.AppendEventsTest do
  alias Commanded.EventStore.Adapters.InMemory

  use Commanded.EventStore.InMemoryTestCase
  use Commanded.EventStore.AppendEventsTestCase, event_store: InMemory
end
