defmodule Commanded.UUIDGenerator.IdApp do
  use Commanded.Application,
    otp_app: :commanded,
    event_store: [
      adapter: Commanded.EventStore.Adapters.InMemory,
      serializer: Commanded.Serialization.JsonSerializer
    ],
    uuid_generator: &Commanded.UUIDGenerator.IdGenerator.increment/0

  alias Commanded.UUIDGenerator.IdAppRouter

  router(IdAppRouter)
end
