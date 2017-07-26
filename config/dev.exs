use Mix.Config

config :commanded,
  :event_store_adapter, Commanded.EventStore.Adapters.InMemory
