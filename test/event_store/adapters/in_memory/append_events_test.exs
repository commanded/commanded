defmodule Commanded.EventStore.Adapters.InMemory.AppendEventsTest do
  use Commanded.EventStore.AppendEventsTestCase

  alias Commanded.EventStore.Adapters.InMemory

  setup do
    InMemory.reset!()
    :ok
  end
end
