defmodule Commanded.Commands.DefaultDispatchReturnApp do
  alias Commanded.ExampleDomain.BankRouter

  use Commanded.Application,
    otp_app: :commanded,
    event_store: [
      adapter: Commanded.EventStore.Adapters.InMemory,
      serializer: Commanded.Serialization.JsonSerializer
    ],
    pubsub: :local,
    registry: :local,
    default_dispatch_opts: [
      consistency: :eventual,
      returning: :aggregate_version
    ]

  router(BankRouter)
end
