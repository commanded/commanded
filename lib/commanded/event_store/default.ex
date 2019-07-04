defmodule Commanded.EventStore.Default do
  @behaviour Commanded.EventStore

  def child_spec(application, event_store_adapter),
    do: event_store_adapter.child_spec(application)
end
