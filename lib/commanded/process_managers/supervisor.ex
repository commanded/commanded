defmodule Commanded.ProcessManagers.Supervisor do
  @moduledoc false

  use Supervisor

  def start_link do
    Supervisor.start_link(__MODULE__, :ok)
  end

  def start_process_manager(supervisor, opts) do
    Supervisor.start_child(supervisor, [opts])
  end

  def init(:ok) do
    children = [
      worker(Commanded.ProcessManagers.ProcessManagerInstance, [], restart: :temporary)
    ]

    supervise(children, strategy: :simple_one_for_one)
  end
end
