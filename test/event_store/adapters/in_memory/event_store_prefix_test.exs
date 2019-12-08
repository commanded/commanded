defmodule Commanded.EventStore.Adapters.InMemory.EventStorePrefixTest do
  alias Commanded.EventStore.Adapters.InMemory

  use Commanded.EventStore.EventStorePrefixTestCase, event_store: InMemory

  def start_event_store(config) do
    {:ok, child_spec, event_store_meta} = InMemory.child_spec(InMemory, config)

    for child <- child_spec do
      start_supervised!(child)
    end

    {:ok, event_store_meta}
  end
end
