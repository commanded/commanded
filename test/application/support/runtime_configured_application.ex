defmodule Commanded.RuntimeConfiguredApplication do
  alias Commanded.EventStore.Adapters.InMemory
  alias Commanded.Serialization.JsonSerializer

  use Commanded.Application, otp_app: :commanded

  def init(config) do
    config =
      config
      |> Keyword.put(:event_store, adapter: InMemory, serializer: JsonSerializer)
      |> Keyword.put(:pubsub, phoenix_pubsub: [adapter: Phoenix.PubSub.PG2, pool_size: 1])
      |> Keyword.put(:registry, :local)

    {:ok, config}
  end
end
