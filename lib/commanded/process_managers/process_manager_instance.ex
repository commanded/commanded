defmodule Commanded.ProcessManagers.ProcessManagerInstance do
  @moduledoc """
  Defines an instance of a process manager.
  """
  use GenServer
  require Logger

  alias Commanded.ProcessManagers.ProcessManagerInstance

  defstruct command_dispatcher: nil, process_manager_module: nil, process_uuid: nil, process_state: nil

  def start_link(command_dispatcher, process_manager_module, process_uuid) do
    GenServer.start_link(__MODULE__, %ProcessManagerInstance{
      command_dispatcher: command_dispatcher,
      process_manager_module: process_manager_module,
      process_uuid: process_uuid,
      process_state: process_manager_module.new(process_uuid)
    })
  end

  def init(%ProcessManagerInstance{} = state) do
    GenServer.cast(self, {:fetch_state})
    {:ok, state}
  end

  @doc """
  Handle the given event by calling the process manager module
  """
  def process_event(process_manager, event) do
    GenServer.call(process_manager, {:process_event, event})
  end

  @doc """
  Attempt to fetch intial process state from snapshot storage
  """
  def handle_cast({:fetch_state}, %ProcessManagerInstance{process_uuid: process_uuid, process_manager_module: process_manager_module} = state) do
    state = case EventStore.read_snapshot(process_uuid) do
      {:ok, snapshot} -> %ProcessManagerInstance{state | process_state: process_manager_module.new(process_uuid, snapshot.data)}
      {:error, :snapshot_not_found} -> state
    end

    {:noreply, state}
  end

  @doc """
  Fetch the process state of this instance
  """
  def process_state(process_manager) do
    GenServer.call(process_manager, {:process_state})
  end

  def handle_call({:process_state}, _from, %ProcessManagerInstance{process_state: process_state} = state) do
    {:reply, process_state.state, state}
  end

  @doc """
  Handle the given event, using the process manager module, against the current process state
  """
  def handle_call({:process_event, event}, _from, %ProcessManagerInstance{command_dispatcher: command_dispatcher, process_manager_module: process_manager_module, process_uuid: process_uuid, process_state: process_state} = state) do
    process_state =
      process_state
      |> process_event(event, process_manager_module)
      |> dispatch_commands(command_dispatcher)
      |> persist_state(process_manager_module, process_uuid)

    state = %ProcessManagerInstance{state | process_state: process_state}

    {:reply, :ok, state}
  end

  defp process_event(process_state, event, process_manager_module) do
    {:ok, process_state} = process_manager_module.handle(process_state, event)
    process_state
  end

  defp dispatch_commands(%{commands: commands} = process_state, command_dispatcher) when is_list(commands) do
    Enum.each(commands, fn command -> command_dispatcher.dispatch(command) end)

    %{process_state | commands: []}
  end

  defp persist_state(process_state, process_manager_module, process_uuid) do
    :ok = EventStore.record_snapshot(%EventStore.Snapshots.SnapshotData{
      source_uuid: process_uuid,
      source_version: 1,
      source_type: Atom.to_string(Module.concat(process_manager_module, State)),
      data: process_state.state
    })

    process_state
  end
end
