defmodule Commanded.EventStore.Adapters.InMemory.SubscriptionTest do
  use Commanded.EventStore.SubscriptionTestCase, application: InMemoryApplication

  defp event_store_wait(default \\ nil), do: default
end
