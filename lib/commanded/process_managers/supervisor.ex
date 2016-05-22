defmodule Commanded.ProcessManagers.Supervisor do
  @moduledoc """
  Supervise zero, one or more process manager instances
  """

  use Supervisor
  require Logger

  def start_link do
    Supervisor.start_link(__MODULE__, nil)
  end

  def start_process_manager(supervisor, process_manager_module, process_uuid) do
    Logger.debug(fn -> "starting process manager process for `#{process_manager_module}` with uuid #{process_uuid}" end)

    Supervisor.start_child(supervisor, [process_manager_module, process_uuid])
  end

  def init(_) do
    children = [
      worker(Commanded.ProcessManagers.ProcessManager, [], restart: :temporary),
    ]

    supervise(children, strategy: :simple_one_for_one)
  end
end
