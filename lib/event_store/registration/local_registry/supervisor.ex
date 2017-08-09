defmodule EventStore.Registration.LocalRegistry.Supervisor do
  use Supervisor

  def start_link(config) do
    Supervisor.start_link(__MODULE__, [config], name: __MODULE__)
  end

  def init(_) do
    children = [
      supervisor(Registry, [:unique, EventStore.Registration.LocalRegistry], id: :event_store_local_registry),
      supervisor(Registry, [:duplicate, EventStore.Subscriptions.PubSub, [partitions: System.schedulers_online]], id: :subscriptions_pubsub_registry),
    ]

    supervise(children, strategy: :one_for_one)
  end
end
