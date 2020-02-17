defmodule Commanded.DistributedApp do
  alias Commanded.EventStore.Adapters.InMemory
  alias Commanded.Serialization.JsonSerializer

  use Commanded.Application,
    otp_app: :commanded,
    event_store: [
      adapter: InMemory,
      serializer: JsonSerializer
    ],
    pubsub: [
      phoenix_pubsub: [
        adapter: Phoenix.PubSub.PG2,
        pool_size: 1
      ]
    ],
    registry: :global
end
