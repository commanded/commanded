defmodule Commanded.UUIDGenerator.IncorrectApp do
  use Commanded.Application,
    otp_app: :commanded,
    event_store: [
      adapter: Commanded.EventStore.Adapters.InMemory,
      serializer: Commanded.Serialization.JsonSerializer
    ],
    uuid_generator: &Commanded.UUIDGenerator.IdGenerator.incorrect/2

  alias Commanded.UUIDGenerator.IdAppRouter

  router(IdAppRouter)
end
