defmodule EventStore.Supervisor do
  use Supervisor

  def start_link do
    Supervisor.start_link(__MODULE__, nil)
  end

  def init(_) do
    children = [
      supervisor(Registry, [:unique, EventStore.Streams]),
      supervisor(EventStore.Storage.PoolSupervisor, []),
      worker(EventStore.Streams.Supervisor, []),
      worker(EventStore.Subscriptions, []),
      worker(EventStore.Writer, [])
    ]

    supervise(children, strategy: :one_for_one)
  end
end
