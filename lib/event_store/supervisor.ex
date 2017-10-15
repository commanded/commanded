defmodule EventStore.Supervisor do
  @moduledoc false
  use Supervisor

  alias EventStore.Registration

  def start_link(config) do
    serializer = EventStore.configured_serializer()

    Supervisor.start_link(__MODULE__, [config, serializer])
  end

  def init([config, serializer]) do
    children = [
      {Postgrex, postgrex_opts(config)},
      Supervisor.child_spec({Registry, [keys: :unique, name: EventStore.Subscriptions.Subscription]}, id: :event_store_subscriptions),
      Supervisor.child_spec({Registry, [keys: :duplicate, name: EventStore.Subscriptions.PubSub, partitions: System.schedulers_online]}, id: :event_store_pub_sub),
      {EventStore.Subscriptions.Supervisor, []},
      {EventStore.Streams.Supervisor, serializer},
      {EventStore.Publisher, serializer},
    ] ++ Registration.child_spec()

    Supervisor.init(children, strategy: :one_for_one)
  end

  defp postgrex_opts(config) do
    [pool_size: 10, pool_overflow: 0]
    |> Keyword.merge(config)
    |> Keyword.take([:username, :password, :database, :hostname, :port, :pool, :pool_size, :pool_overflow])
    |> Keyword.merge(name: :event_store)
  end
end
