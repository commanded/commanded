defmodule Commanded.ProcessManagers.ProcessManager do
  @moduledoc """
  Process to provide access to a process manager.
  """
  use GenServer
  require Logger

  alias Commanded.ProcessManagers.ProcessManager
  alias Commanded.Commands.Dispatcher

  @event_retries 3

  defstruct command_dispatcher: nil, process_manager_module: nil, process_uuid: nil, process_state: nil

  def start_link(command_dispatcher, process_manager_module, process_uuid) do
    GenServer.start_link(__MODULE__, %ProcessManager{
      command_dispatcher: command_dispatcher,
      process_manager_module: process_manager_module,
      process_uuid: process_uuid,
      process_state: process_manager_module.new(process_uuid)
    })
  end

  def init(%ProcessManager{} = state) do
    {:ok, state}
  end

  @doc """
  Handle the given event by calling the process manager module
  """
  def process_event(server, event) do
    GenServer.call(server, {:process_event, event})
  end

  @doc """
  Handle the given event, using the process manager module, against the current process state
  """
  def handle_call({:process_event, event}, _from, %ProcessManager{command_dispatcher: command_dispatcher, process_manager_module: process_manager_module, process_uuid: process_uuid, process_state: process_state} = state) do
    process_state =
      process_state
      |> process_event(event, process_manager_module, @event_retries)
      |> persist_state(process_manager_module, process_uuid, event)
      |> dispatch_commands(command_dispatcher)

    state = %ProcessManager{state | process_state: process_state}

    {:reply, :ok, state}
  end

  defp process_event(process_state, event, process_manager_module, retries) when retries > 0 do
    process_manager_module.handle(process_state, event)
  end

  defp persist_state(process_state, process_manager_module, process_uuid, event) do
    EventStore.record_snapshot(%EventStore.Snapshots.SnapshotData{
      source_uuid: process_uuid,
      source_version: 1,
      source_type: Atom.to_string(process_manager_module),
      data: process_state
    })

    process_state
  end

  defp dispatch_commands(%{commands: commands} = process_state, command_dispatcher) when is_list(commands) do
    Enum.each(commands, fn command -> command_dispatcher.dispatch(command) end)

    %{process_state | commands: []}
  end
end
