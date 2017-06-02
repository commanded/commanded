defmodule Commanded.Supervisor do
  use Supervisor
  use Commanded.EventStore

  def start_link do
    Supervisor.start_link(__MODULE__, nil)
  end

  def init(_) do
    children = [
      supervisor(Task.Supervisor, [[name: Commanded.Commands.TaskDispatcher]]),
      supervisor(Commanded.Aggregates.Supervisor, []),
    ]

    supervise(children, strategy: :one_for_one)
  end
end
