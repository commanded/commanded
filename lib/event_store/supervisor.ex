defmodule EventStore.Supervisor do
  use Supervisor

  def start_link do
    Supervisor.start_link(__MODULE__, nil)
  end

  def init(_) do
    children = [
      supervisor(EventStore.Storage.PoolSupervisor, []),
      worker(EventStore.Streams, []),
      worker(EventStore.Subscriptions, []),
      worker(EventStore.Publisher, []),
      worker(EventStore.Writer, [])
    ]

    supervise(children, strategy: :one_for_one)
  end
end
