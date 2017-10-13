defmodule Commanded.ProcessManagers.ProcessManagerInstance do
  @moduledoc false
  use GenServer

  require Logger

  alias Commanded.ProcessManagers.{
    ProcessRouter,
    ProcessManagerInstance,
  }
  alias Commanded.EventStore
  alias Commanded.EventStore.{
    RecordedEvent,
    SnapshotData,
  }

  defstruct [
    command_dispatcher: nil,
    process_manager_name: nil,
    process_manager_module: nil,
    process_uuid: nil,
    process_state: nil,
    last_seen_event: nil,
  ]

  def start_link(command_dispatcher, process_manager_name, process_manager_module, process_uuid) do
    GenServer.start_link(__MODULE__, %ProcessManagerInstance{
      command_dispatcher: command_dispatcher,
      process_manager_name: process_manager_name,
      process_manager_module: process_manager_module,
      process_uuid: process_uuid,
      process_state: struct(process_manager_module),
    })
  end

  def init(%ProcessManagerInstance{} = state) do
    GenServer.cast(self(), :fetch_state)
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
    GenServer.call(process_manager, :stop)
  end

  @doc """
  Fetch the process state of this instance
  """
  def process_state(process_manager) do
    GenServer.call(process_manager, :process_state)
  end

  @doc false
  def handle_call(:stop, _from, %ProcessManagerInstance{} = state) do
    :ok = delete_state(state)

    # stop the process with a normal reason
    {:stop, :normal, :ok, state}
  end

  @doc false
  def handle_call(:process_state, _from, %ProcessManagerInstance{process_state: process_state} = state) do
    {:reply, process_state, state}
  end

  @doc """
  Attempt to fetch intial process state from snapshot storage
  """
  def handle_cast(:fetch_state, %ProcessManagerInstance{} = state) do
    state = case EventStore.read_snapshot(process_state_uuid(state)) do
      {:ok, snapshot} ->
        %ProcessManagerInstance{state |
          process_state: snapshot.data,
          last_seen_event: snapshot.source_version,
        }

      {:error, :snapshot_not_found} -> state
    end

    {:noreply, state}
  end

  @doc """
  Handle the given event, using the process manager module, against the current process state
  """
  def handle_cast({:process_event, %RecordedEvent{} = event, process_router}, %ProcessManagerInstance{} = state) do
    case event_already_seen?(event, state) do
      true -> process_seen_event(event, process_router, state)
      false -> process_unseen_event(event, process_router, state)
    end
  end

  defp event_already_seen?(
    %RecordedEvent{event_number: event_number},
    %ProcessManagerInstance{last_seen_event: last_seen_event})
  do
    not is_nil(last_seen_event) and event_number <= last_seen_event
  end

  defp process_seen_event(event = %RecordedEvent{}, process_router, state) do
    # already seen event, so just ack
    :ok = ack_event(event, process_router)

    {:noreply, state}
  end

  defp process_unseen_event(%RecordedEvent{event_number: event_number} = event, process_router, %ProcessManagerInstance{} = state) do
    case handle_event(event, state) do
      {:error, reason} ->
        Logger.error(fn -> describe(state) <> " failed to handle event #{inspect event_number} due to: #{inspect reason}" end)

	      {:stop, reason, state}

      commands ->
        with :ok <- commands |> List.wrap() |> dispatch_commands(state) do
          process_state = mutate_state(event, state)

          state = %ProcessManagerInstance{state |
            process_state: process_state,
            last_seen_event: event_number,
          }

          :ok = persist_state(state, event_number)
          :ok = ack_event(event, process_router)

          {:noreply, state}
        else
          {:stop, reason} ->
            {:stop, reason, state}
        end
    end
  end

  # process instance is given the event and returns applicable commands (may be none, one or many)
  defp handle_event(%RecordedEvent{data: data}, %ProcessManagerInstance{process_manager_module: process_manager_module, process_state: process_state}) do
    process_manager_module.handle(process_state, data)
  end

  # update the process instance's state by applying the event
  defp mutate_state(%RecordedEvent{data: data}, %ProcessManagerInstance{process_manager_module: process_manager_module, process_state: process_state}) do
    process_manager_module.apply(process_state, data)
  end

  defp dispatch_commands(commands, state, context \\ %{})
  defp dispatch_commands([], _state, _context), do: :ok
  defp dispatch_commands([command | pending_commands], %ProcessManagerInstance{command_dispatcher: command_dispatcher} = state, context) do
    Logger.debug(fn -> describe(state) <> " attempting to dispatch command: #{inspect command}" end)

    case command_dispatcher.dispatch(command) do
      :ok ->
        dispatch_commands(pending_commands, state)

      error ->
        Logger.warn(fn -> describe(state) <> " failed to dispatch command #{inspect command} due to: #{inspect error}" end)

        dispatch_failure(error, command, pending_commands, context, state)
    end
  end

  defp dispatch_failure(error, failed_command, pending_commands, context, %ProcessManagerInstance{process_manager_module: process_manager_module} = state) do
    case process_manager_module.error(error, failed_command, context) do
      {:retry, context} ->
        Logger.info(fn -> describe(state) <> " is retrying failed command due to" end)

        dispatch_commands([failed_command | pending_commands], state, context)

      {:retry, delay, context} ->
        Logger.info(fn -> describe(state) <> " is retrying failed command due to: #{inspect error}, retrying after #{inspect delay}ms" end)

        :timer.sleep(delay)

        dispatch_commands([failed_command | pending_commands], state, context)

      :skip ->
        # skip the problematic event, discard any pending commands
        Logger.info(fn -> describe(state) <> " is skipping event and #{length(pending_commands)} pending command(s)" end)

        :ok

      :ignore ->
        # ignore the error, continue dispatching any pending commands
        Logger.info(fn -> describe(state) <> " is ignoring error dispatching command" end)

        dispatch_commands(pending_commands, state)

      {:stop, reason} = reply ->
        # stop process manager
        Logger.warn(fn -> describe(state) <> " has requested to stop: #{inspect reason}" end)

        reply
    end
  end

  defp describe(%ProcessManagerInstance{process_manager_module: process_manager_module}) do
    inspect(process_manager_module)
  end

  defp persist_state(%ProcessManagerInstance{process_manager_module: process_manager_module, process_state: process_state} = state, source_version) do
    EventStore.record_snapshot(%SnapshotData{
      source_uuid: process_state_uuid(state),
      source_version: source_version,
      source_type: Atom.to_string(process_manager_module),
      data: process_state,
    })
  end

  defp delete_state(%ProcessManagerInstance{} = state), do: EventStore.delete_snapshot(process_state_uuid(state))

  defp ack_event(%RecordedEvent{} = event, process_router), do: ProcessRouter.ack_event(process_router, event)

  defp process_state_uuid(%ProcessManagerInstance{process_manager_name: process_manager_name, process_uuid: process_uuid}), do: "#{process_manager_name}-#{process_uuid}"
end
