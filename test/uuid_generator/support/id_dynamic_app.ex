defmodule Commanded.UUIDGenerator.IdDynamicApp do
  use Commanded.Application,
    otp_app: :commanded,
    event_store: [
      adapter: Commanded.EventStore.Adapters.InMemory,
      serializer: Commanded.Serialization.JsonSerializer
    ],
    uuid_generator: &Commanded.UUIDGenerator.IdGenerator.increment/0

  alias Commanded.UUIDGenerator.IdAppDynamicRouter

  router(IdAppDynamicRouter)

  def app_name(app_id) do
    Module.concat([__MODULE__, "id#{app_id}"])
  end
end
