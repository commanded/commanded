defmodule EventStore.Supervisor do
  use Supervisor

  def start_link(config) do
    serializer = EventStore.configured_serializer()

    Supervisor.start_link(__MODULE__, [config, serializer])
  end

  def init([config, serializer]) do
    children = [
      worker(Postgrex, [postgrex_opts(config)]),
      supervisor(Registry, [:unique, EventStore.Streams], id: :streams_registry),
      supervisor(Registry, [:unique, EventStore.Subscriptions], id: :subscriptions_registry),
      supervisor(Registry, [:duplicate, EventStore.Subscriptions.PubSub, [partitions: System.schedulers_online]], id: :subscriptions_pubsub_registry),
      worker(EventStore.Publisher, [serializer]),
      supervisor(EventStore.Subscriptions.Supervisor, []),
      supervisor(EventStore.Streams.Supervisor, [serializer]),
    ]

    supervise(children, strategy: :one_for_one)
  end

  defp postgrex_opts(config) do
    [pool_size: 10, pool_overflow: 0]
    |> Keyword.merge(config)
    |> Keyword.take([:username, :password, :database, :hostname, :port, :pool, :pool_size, :pool_overflow])
    |> Keyword.merge(name: :event_store)
  end
end
