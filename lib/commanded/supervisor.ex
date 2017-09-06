defmodule Commanded.Supervisor do
  @moduledoc false
  use Supervisor
  use Commanded.Registration

  def start_link do
    Supervisor.start_link(__MODULE__, [])
  end

  def init(_) do
    children = [
      Supervisor.child_spec({Task.Supervisor, [name: Commanded.Commands.TaskDispatcher]}, []),
      {Commanded.Aggregates.Supervisor, []},
    ] ++ @registry.child_spec()

    Supervisor.init(children, strategy: :one_for_one)
  end
end
