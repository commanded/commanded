defmodule EventStore.Supervisor do
  use Supervisor

  def start_link(config) do
    serializer = EventStore.configured_serializer()

    Supervisor.start_link(__MODULE__, [config, serializer])
  end

  @default_config [
    pool: DBConnection.Poolboy,
    pool_size: 10,
  ]

  def init([config, serializer]) do
    children = [
      worker(Postgrex, [postgrex_opts(config)]),
      supervisor(Registry, [:unique, EventStore.Streams], id: :streams_registry),
      supervisor(Registry, [:unique, EventStore.Subscriptions], id: :subscriptions_registry),
      supervisor(Registry, [:duplicate, EventStore.Subscriptions.PubSub, [partitions: System.schedulers_online]], id: :subscriptions_pubsub_registry),
      supervisor(EventStore.Subscriptions.Supervisor, []),
      supervisor(EventStore.Streams.Supervisor, [serializer]),
      worker(EventStore.Writer, [serializer]),
    ]

    supervise(children, strategy: :one_for_one)
  end

  defp postgrex_opts(config) do
    @default_config
    |> Keyword.merge(config)
    |> Keyword.take([:username, :password, :database, :hostname, :port, :pool, :pool_size])
    |> Keyword.merge(name: :event_store)
  end
end
