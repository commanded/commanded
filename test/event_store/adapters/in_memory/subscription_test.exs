defmodule Commanded.EventStore.Adapters.InMemory.SubscriptionTest do
  alias Commanded.EventStore.Adapters.InMemory

  use Commanded.EventStore.SubscriptionTestCase, event_store: InMemory

  setup do
    child_spec = InMemory.child_spec(InMemory, serializer: Commanded.Serialization.JsonSerializer)

    for child <- child_spec, do: start_supervised!(child)

    :ok
  end

  defp event_store_wait(default \\ nil), do: default
end
