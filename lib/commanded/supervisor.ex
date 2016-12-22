defmodule Commanded.Supervisor do
  use Supervisor

  def start_link do
    Supervisor.start_link(__MODULE__, nil)
  end

  def init(_) do
    children = [
      worker(Commanded.Aggregates.Registry, []),
      supervisor(Task.Supervisor, [[name: Commanded.Commands.TaskDispatcher]]),
      supervisor(Commanded.EventStore.Supervisor, [])
    ]

    supervise(children, strategy: :one_for_one)
  end
end
