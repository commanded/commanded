defmodule Commanded.EventStore.EventStoreTestCase do
  use ExUnit.CaseTemplate

  alias Commanded.EventStore.Adapters.EventStore
  alias Commanded.EventStore.Adapters.EventStore.Storage

  setup_all do
    config = Storage.config()

    {:ok, conn} = Storage.connect(config)

    [config: config, conn: conn]
  end

  setup %{config: config, conn: conn} do
    {:ok, event_store_meta} = start_event_store()

    on_exit(fn ->
      Storage.reset!(conn, config)
    end)

    [event_store_meta: event_store_meta]
  end

  def start_event_store(config \\ []) do
    alias Commanded.EventStore.Adapters.EventStore

    config = Keyword.put_new(config, :event_store, TestEventStore)

    {:ok, child_spec, event_store_meta} = EventStore.child_spec(EventStoreApplication, config)

    for child <- child_spec do
      start_supervised!(child)
    end

    {:ok, event_store_meta}
  end
end
