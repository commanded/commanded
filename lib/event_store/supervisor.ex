defmodule EventStore.Supervisor do
  use Supervisor

  def start_link do
    Supervisor.start_link(__MODULE__, nil)
  end

  def init(_) do
    children = [
      supervisor(Registry, [:unique, EventStore.Streams], id: :streams_registry),
      supervisor(Registry, [:unique, EventStore.Subscriptions], id: :subscriptions_registry),
      supervisor(Registry, [:duplicate, EventStore.Subscriptions.PubSub, [partitions: System.schedulers_online]], id: :subscriptions_pubsub_registry),
      supervisor(EventStore.Storage.PoolSupervisor, []),
      supervisor(EventStore.Subscriptions.Supervisor, []),
      supervisor(EventStore.Streams.Supervisor, []),
      worker(EventStore.Writer, [])
    ]

    supervise(children, strategy: :one_for_one)
  end
end
