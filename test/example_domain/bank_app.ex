defmodule Commanded.ExampleDomain.BankApp do
  alias Commanded.EventStore.Adapters.InMemory
  alias Commanded.ExampleDomain.BankRouter
  alias Commanded.Serialization.JsonSerializer

  use Commanded.Application,
    otp_app: :commanded,
    event_store: [
      adapter: InMemory,
      serializer: JsonSerializer
    ],
    pubsub: :local,
    registry: :local

  router(BankRouter)
end
