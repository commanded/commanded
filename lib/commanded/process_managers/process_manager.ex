defmodule Commanded.ProcessManagers.ProcessManager do
  @moduledoc """
  Process to provide access to a process manager.
  """
  use GenServer
  require Logger

  alias Commanded.ProcessManagers.ProcessManager

  @event_retries 3

  defstruct process_manager_module: nil, process_uuid: nil, process_state: nil

  def start_link(process_manager_module, process_uuid) do
    GenServer.start_link(__MODULE__, {process_manager_module, process_uuid})
  end

  def init({process_manager_module, process_uuid}) do
    state = %ProcessManager{process_manager_module: process_manager_module, process_uuid: process_uuid, process_state: struct(process_manager_module)}

    {:ok, state}
  end

  @doc """
  Handle the given event by calling the process manager module
  """
  def handle(server, event) do
    GenServer.call(server, {:process_event, event})
  end

  @doc """
  Handle the given event, using the process manager module, against the current process state
  """
  def handle_call({:process_event, event}, _from, %ProcessManager{process_manager_module: process_manager_module, process_state: process_state} = state) do
    process_state = process_event(event, process_manager_module, process_state, @event_retries)

    # TODO: dispatch any commands

    state = %ProcessManager{state | process_state: process_state}

    {:reply, :ok, state}
  end

  defp process_event(event, process_manager_module, process_state, retries) when retries > 0 do
    process_manager_module.handle(process_state, event)
  end
end
