defmodule EventStore.Supervisor do
  use Supervisor

  def start_link(config) do
    serializer = EventStore.configured_serializer()

    Supervisor.start_link(__MODULE__, [config, serializer])
  end

  def init([config, serializer]) do
    children = [
      worker(Postgrex, [postgrex_opts(config)]),
      worker(EventStore.Publisher, [serializer]),
      supervisor(EventStore.Registration.LocalRegistry, [config]),
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
