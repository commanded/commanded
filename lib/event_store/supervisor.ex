defmodule EventStore.Supervisor do
  use Supervisor

  def start_link(config) do
    serializer = EventStore.configured_serializer()

    Supervisor.start_link(__MODULE__, [config, serializer])
  end

  def init([config, serializer]) do
    registry_provider = registry_provider(config)
    registry_supervision = config |> registry_provider.child_spec() |> List.wrap()
      
    children = [
      {Postgrex, postgrex_opts(config)},
      {EventStore.Publisher, serializer},
      {EventStore.Subscriptions.Supervisor, []},
      {EventStore.Streams.Supervisor, serializer}
    ] ++ registry_supervision

    Supervisor.init(children, strategy: :one_for_one)
  end

  defp registry_provider(config) do
    config
    |> Keyword.get(:registry, :local)
    |> case do
      :local       -> EventStore.Registration.LocalRegistry
      :distributed -> EventStore.Registration.Distributed
      unknown      -> raise ArgumentError, message: "Unknown :registry setting in config: #{inspect unknown}"
    end
  end

  defp postgrex_opts(config) do
    [pool_size: 10, pool_overflow: 0]
    |> Keyword.merge(config)
    |> Keyword.take([:username, :password, :database, :hostname, :port, :pool, :pool_size, :pool_overflow])
    |> Keyword.merge(name: :event_store)
  end
end
