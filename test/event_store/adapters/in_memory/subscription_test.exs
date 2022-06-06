defmodule Commanded.EventStore.Adapters.InMemory.SubscriptionTest do
  alias Commanded.EventStore.Adapters.InMemory

  use Commanded.EventStore.InMemoryTestCase
  use Commanded.EventStore.SubscriptionTestCase, event_store: InMemory

  defp event_store_wait(_default \\ nil), do: 1
end
