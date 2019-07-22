defmodule Commanded.EventStore.Adapters.InMemory.SnapshotTest do
  alias Commanded.EventStore.Adapters.InMemory

  use Commanded.EventStore.SnapshotTestCase, event_store: InMemory

  setup do
    child_spec = InMemory.child_spec(InMemory, serializer: Commanded.Serialization.JsonSerializer)

    for child <- child_spec, do: start_supervised!(child)

    :ok
  end
end
