defmodule EventStore.Supervisor do
  use Supervisor

  def start_link do
    serializer = EventStore.configured_serializer()

    Supervisor.start_link(__MODULE__, serializer)
  end

  def init(serializer) do
    children = [
      supervisor(Registry, [:unique, EventStore.Streams], id: :streams_registry),
      supervisor(Registry, [:unique, EventStore.Subscriptions], id: :subscriptions_registry),
      supervisor(Registry, [:duplicate, EventStore.Subscriptions.PubSub, [partitions: System.schedulers_online]], id: :subscriptions_pubsub_registry),
      supervisor(EventStore.Storage.PoolSupervisor, []),
      supervisor(EventStore.Subscriptions.Supervisor, []),
      supervisor(EventStore.Streams.Supervisor, [serializer]),
      worker(EventStore.Writer, [serializer])
    ]

    supervise(children, strategy: :one_for_one)
  end
end
