defmodule Commanded.EventStore.Adapters.EventStore.EventStorePrefixTest do
  use Commanded.EventStore.EventStorePrefixTestCase,
    event_store: Commanded.EventStore.Adapters.EventStore

  @moduletag :eventstore_adapter

  alias Commanded.EventStore.Adapters.EventStore.Storage
  alias Commanded.EventStore.EventStoreTestCase
  alias EventStore.Tasks.Create
  alias EventStore.Tasks.Init

  setup_all do
    config1 = Storage.config("prefix1")
    config2 = Storage.config("prefix2")

    {:ok, conn1} = Storage.connect(config1)
    {:ok, conn2} = Storage.connect(config2)

    create_init_store!(config1)
    create_init_store!(config2)

    [config1: config1, config2: config2, conn1: conn1, conn2: conn2]
  end

  setup %{config1: config1, config2: config2, conn1: conn1, conn2: conn2} do
    on_exit(fn ->
      Storage.reset!(conn1, config1)
      Storage.reset!(conn2, config2)
    end)
  end

  defdelegate start_event_store(config), to: EventStoreTestCase

  defp create_init_store!(config) do
    Create.exec(config, quiet: true)
    Init.exec(config, quiet: true)
  end
end
