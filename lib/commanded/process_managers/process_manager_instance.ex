defmodule Commanded.ProcessManagers.ProcessManagerInstance do
  @moduledoc """
  Defines an instance of a process manager.
  """

  use GenServer
  use Commanded.EventStore
  require Logger
  
  alias Commanded.ProcessManagers.{ProcessRouter,ProcessManagerInstance}
  alias Commanded.EventStore.{RecordedEvent,SnapshotData}
  
  defstruct [
    command_dispatcher: nil,
    process_manager_name: nil,
    process_manager_module: nil,
    process_uuid: nil,
    process_state: nil,
    last_seen_events: nil,
  ]

  def start_link(command_dispatcher, process_manager_name, process_manager_module, process_uuid) do
    GenServer.start_link(__MODULE__, %ProcessManagerInstance{
      command_dispatcher: command_dispatcher,
      process_manager_name: process_manager_name,
      process_manager_module: process_manager_module,
      process_uuid: process_uuid,
      process_state: struct(process_manager_module),
      last_seen_events: %{}
    })
  end

  def init(%ProcessManagerInstance{} = state) do
    GenServer.cast(self, {:fetch_state})
    {:ok, state}
  end

  @doc """
  Handle the given event by delegating to the process manager module
  """
  def process_event(process_manager, %RecordedEvent{} = event, process_router) do
    GenServer.cast(process_manager, {:process_event, event, process_router})
  end

  @doc """
  Stop the given process manager and delete its persisted state.

  Typically called when it has reached its final state.
  """
  def stop(process_manager) do
    GenServer.call(process_manager, {:stop})
  end

  @doc """
  Fetch the process state of this instance
  """
  def process_state(process_manager) do
    GenServer.call(process_manager, {:process_state})
  end

  def handle_call({:stop}, _from, %ProcessManagerInstance{} = state) do
    delete_state(state)

    # stop the process with a normal reason
    {:stop, :normal, :ok, state}
  end

  def handle_call({:process_state}, _from, %ProcessManagerInstance{process_state: process_state} = state) do
    {:reply, process_state, state}
  end

  @doc """
  Attempt to fetch intial process state from snapshot storage
  """
  def handle_cast({:fetch_state}, %ProcessManagerInstance{} = state) do
    state = case @event_store.read_snapshot(process_state_uuid(state)) do
      {:ok, snapshot} ->
        %ProcessManagerInstance{state |
          process_state: snapshot.data,
          last_seen_events: Map.put(state.last_seen_events, snapshot.source_stream_id, snapshot.source_version),
        }

      {:error, :snapshot_not_found} ->
        state
    end

    {:noreply, state}
  end

  @doc """
  Handle the given event, using the process manager module, against the current process state
  """
  def handle_cast({:process_event, %RecordedEvent{} = event, process_router}, %ProcessManagerInstance{} = state) do
    state = case event_already_seen?(event, state) do
	      true -> process_seen_event(event, process_router, state)
	      false -> process_unseen_event(event, process_router, state)
	    end

    {:noreply, state}
  end 

  defp event_already_seen?(%RecordedEvent{stream_id: stream_id, stream_version: stream_version}, %ProcessManagerInstance{last_seen_events: last_seen_events}) do
    last_seen_stream_version = Map.get(last_seen_events, stream_id)

    not is_nil(last_seen_stream_version) and stream_version <= last_seen_stream_version
  end

  defp process_seen_event(event = %RecordedEvent{}, process_router, state) do
    # already seen event, so just ack
    ack_event(event, process_router)

    state
  end

  defp process_unseen_event(%RecordedEvent{stream_id: stream_id, stream_version: stream_version} = event, process_router, %ProcessManagerInstance{command_dispatcher: command_dispatcher, process_manager_module: process_manager_module, process_state: process_state, last_seen_events: last_seen_events} = state) do
    case handle_event(process_manager_module, process_state, event) do
      {:error, reason} ->
        Logger.warn(fn -> "process manager instance failed to handle event id #{inspect stream_id}|#{inspect stream_version} due to: #{inspect reason}" end)

	state
      commands ->
        :ok = dispatch_commands(List.wrap(commands), command_dispatcher)

        process_state = mutate_state(process_manager_module, process_state, event)

        state = %ProcessManagerInstance{state |
          process_state: process_state,
          last_seen_events: Map.put(last_seen_events, stream_id, stream_version)
        }

        persist_state(state, stream_id, stream_version)
        ack_event(event, process_router)

	state
    end
  end

  # process instance is given the event and returns applicable commands (may be none, one or many)
  defp handle_event(process_manager_module, process_state, %RecordedEvent{data: data}) do
    process_manager_module.handle(process_state, data)
  end

  # update the process instance's state by applying the event
  defp mutate_state(process_manager_module, process_state, %RecordedEvent{data: data}) do
    process_manager_module.apply(process_state, data)
  end

  defp dispatch_commands([], _command_dispatcher), do: :ok
  defp dispatch_commands(commands, command_dispatcher) when is_list(commands) do
    Enum.each(commands, fn command ->
      Logger.debug(fn -> "process manager instance attempting to dispatch command: #{inspect command}" end)
      :ok = command_dispatcher.dispatch(command)
    end)
  end

  defp persist_state(%ProcessManagerInstance{process_manager_module: process_manager_module, process_state: process_state} = state, stream_id, stream_version) do
    :ok = @event_store.record_snapshot(%SnapshotData{
      source_uuid: process_state_uuid(state),
      source_version: stream_version,
      source_stream_id: stream_id,
      source_type: Atom.to_string(process_manager_module),
      data: process_state
    })
  end

  defp ack_event(%RecordedEvent{} = event, process_router) do
    :ok = ProcessRouter.ack_event(process_router, event)
  end

  defp delete_state(%ProcessManagerInstance{} = state) do
    :ok = @event_store.delete_snapshot(process_state_uuid(state))
  end

  defp process_state_uuid(%ProcessManagerInstance{process_manager_name: process_manager_name, process_uuid: process_uuid}), do: "#{process_manager_name}-#{process_uuid}"
end
