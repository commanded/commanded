defmodule EventStore.Supervisor do
  use Supervisor
  use EventStore.Registration

  def start_link(config) do
    serializer = EventStore.configured_serializer()

    Supervisor.start_link(__MODULE__, [config, serializer])
  end

  def init([config, serializer]) do
    registry_supervision = config |> @registry.child_spec() |> List.wrap()

    children = [
      {Postgrex, postgrex_opts(config)},
      {EventStore.Publisher, serializer},
      {EventStore.Subscriptions.Supervisor, []},
      {EventStore.Streams.Supervisor, serializer}
    ] ++ registry_supervision

    Supervisor.init(children, strategy: :one_for_one)
  end

  defp postgrex_opts(config) do
    [pool_size: 10, pool_overflow: 0]
    |> Keyword.merge(config)
    |> Keyword.take([:username, :password, :database, :hostname, :port, :pool, :pool_size, :pool_overflow])
    |> Keyword.merge(name: :event_store)
  end
end
