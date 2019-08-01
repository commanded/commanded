defmodule Commanded.ProcessManagers.Supervisor do
  @moduledoc false

  use DynamicSupervisor

  alias Commanded.ProcessManagers.ProcessManagerInstance

  def start_link do
    DynamicSupervisor.start_link(__MODULE__, [])
  end

  def start_process_manager(supervisor, opts) do
    DynamicSupervisor.start_child(supervisor, {ProcessManagerInstance, opts})
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end
