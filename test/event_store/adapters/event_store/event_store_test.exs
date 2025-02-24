defmodule Commanded.EventStore.Adapters.EventStore.EventStoreTest do
  use ExUnit.Case

  setup do
    start_supervised!(EventStoreApplication)

    :ok
  end

  test "should configure event store in application" do
    assert {Commanded.EventStore.Adapters.EventStore, %{event_store: TestEventStore}} =
             Commanded.Application.event_store_adapter(EventStoreApplication)
  end
end
