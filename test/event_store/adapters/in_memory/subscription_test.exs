defmodule Commanded.EventStore.Adapters.InMemory.SubscriptionTest do
  use Commanded.EventStore.SubscriptionTestCase

  alias Commanded.EventStore.Adapters.InMemory

  setup do
    InMemory.reset!()
    :ok
  end

  defp event_store_wait(default \\ nil), do: default
end
