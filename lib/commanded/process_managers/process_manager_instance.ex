defmodule Commanded.ProcessManagers.ProcessManagerInstance do
  @moduledoc false

  use GenServer, restart: :temporary

  require Logger

  alias Commanded.Application
  alias Commanded.ProcessManagers.{ProcessRouter, FailureContext}
  alias Commanded.EventStore
  alias Commanded.EventStore.{RecordedEvent, SnapshotData}

  defmodule State do
    @moduledoc false

    defstruct [
      :application,
      :idle_timeout,
      :process_router,
      :process_manager_name,
      :process_manager_module,
      :process_uuid,
      :process_state,
      :last_seen_event
    ]
  end

  def start_link(opts) do
    process_manager_module = Keyword.fetch!(opts, :process_manager_module)

    state = %State{
      application: Keyword.fetch!(opts, :application),
      idle_timeout: Keyword.fetch!(opts, :idle_timeout),
      process_router: Keyword.fetch!(opts, :process_router),
      process_manager_name: Keyword.fetch!(opts, :process_manager_name),
      process_manager_module: process_manager_module,
      process_uuid: Keyword.fetch!(opts, :process_uuid),
      process_state: struct(process_manager_module)
    }

    GenServer.start_link(__MODULE__, state)
  end

  @doc """
  Checks whether or not the process manager has already processed events
  """
  def new?(instance) do
    GenServer.call(instance, :new?)
  end

  @doc """
  Handle the given event by delegating to the process manager module
  """
  def process_event(instance, %RecordedEvent{} = event) do
    GenServer.cast(instance, {:process_event, event})
  end

  @doc """
  Stop the given process manager and delete its persisted state.

  Typically called when it has reached its final state.
  """
  def stop(instance) do
    GenServer.call(instance, :stop)
  end

  @doc """
  Fetch the process state of this instance
  """
  def process_state(instance) do
    GenServer.call(instance, :process_state)
  end

  @doc """
  Get the current process manager instance's identity.
  """
  def identity, do: Process.get(:process_uuid)

  @doc false
  @impl GenServer
  def init(%State{} = state) do
    {:ok, state, {:continue, :fetch_state}}
  end

  @doc """
  Attempt to fetch intial process state from snapshot storage.
  """
  @impl GenServer
  def handle_continue(:fetch_state, %State{} = state) do
    %State{application: application, process_uuid: process_uuid} = state

    state =
      case EventStore.read_snapshot(application, snapshot_uuid(state)) do
        {:ok, snapshot} ->
          %State{
            state
            | process_state: snapshot.data,
              last_seen_event: snapshot.source_version
          }

        {:error, :snapshot_not_found} ->
          state
      end

    Process.put(:process_uuid, process_uuid)

    {:noreply, state}
  end

  @doc false
  @impl GenServer
  def handle_call(:stop, _from, %State{} = state) do
    :ok = delete_state(state)

    # Stop the process with a normal reason
    {:stop, :normal, :ok, state}
  end

  @doc false
  @impl GenServer
  def handle_call(:process_state, _from, %State{} = state) do
    %State{idle_timeout: idle_timeout, process_state: process_state} = state

    {:reply, process_state, state, idle_timeout}
  end

  @doc false
  @impl GenServer
  def handle_call(:new?, _from, %State{} = state) do
    %State{idle_timeout: idle_timeout, last_seen_event: last_seen_event} = state

    {:reply, is_nil(last_seen_event), state, idle_timeout}
  end

  @doc """
  Handle the given event, using the process manager module, against the current process state
  """
  @impl GenServer
  def handle_cast({:process_event, event}, %State{} = state) do
    case event_already_seen?(event, state) do
      true -> process_seen_event(event, state)
      false -> process_unseen_event(event, state)
    end
  end

  @doc false
  @impl GenServer
  def handle_info(:timeout, %State{} = state) do
    Logger.debug(fn -> describe(state) <> " stopping due to inactivity timeout" end)

    {:stop, :normal, state}
  end

  @doc false
  @impl GenServer
  def handle_info(message, state) do
    Logger.error(fn -> describe(state) <> " received unexpected message: " <> inspect(message) end)

    {:noreply, state}
  end

  defp event_already_seen?(%RecordedEvent{}, %State{last_seen_event: nil}),
    do: false

  defp event_already_seen?(%RecordedEvent{} = event, %State{} = state) do
    %RecordedEvent{event_number: event_number} = event
    %State{last_seen_event: last_seen_event} = state

    event_number <= last_seen_event
  end

  # Already seen event, so just ack.
  defp process_seen_event(%RecordedEvent{} = event, %State{} = state) do
    %State{idle_timeout: idle_timeout} = state

    :ok = ack_event(event, state)

    {:noreply, state, idle_timeout}
  end

  defp process_unseen_event(%RecordedEvent{} = event, %State{} = state, context \\ %{}) do
    %RecordedEvent{correlation_id: correlation_id, event_id: event_id, event_number: event_number} =
      event

    %State{idle_timeout: idle_timeout} = state

    case handle_event(event, state) do
      {:error, _error} = error ->
        failure_context = build_failure_context(event, context, nil, state)

        handle_event_error(error, event, failure_context, state)

      {:error, error, stacktrace} ->
        failure_context = build_failure_context(event, context, stacktrace, state)

        handle_event_error({:error, error}, event, failure_context, state)

      {:stop, _error, _state} = reply ->
        reply

      commands ->
        # Copy event id, as causation id, and correlation id from handled event.
        opts = [causation_id: event_id, correlation_id: correlation_id, returning: false]

        with :ok <- commands |> List.wrap() |> dispatch_commands(opts, state, event) do
          process_state = mutate_state(event, state)

          state = %State{
            state
            | process_state: process_state,
              last_seen_event: event_number
          }

          :ok = persist_state(event_number, state)
          :ok = ack_event(event, state)

          {:noreply, state, idle_timeout}
        else
          {:stop, reason} ->
            {:stop, reason, state}
        end
    end
  end

  # Process instance is given the event and returns applicable commands
  # (may be none, one or many).
  defp handle_event(%RecordedEvent{} = event, %State{} = state) do
    %RecordedEvent{data: data} = event

    %State{
      process_manager_module: process_manager_module,
      process_state: process_state
    } = state

    try do
      process_manager_module.handle(process_state, data)
    rescue
      error ->
        stacktrace = __STACKTRACE__
        Logger.error(fn -> Exception.format(:error, error, stacktrace) end)

        {:error, error, stacktrace}
    end
  end

  defp build_failure_context(failed_event, context, stacktrace, state) do
    %FailureContext{
      context: context,
      last_event: failed_event,
      pending_commands: [],
      process_manager_state: state,
      stacktrace: stacktrace
    }
  end

  defp handle_event_error(
         {:error, reason} = error,
         %RecordedEvent{} = failed_event,
         %FailureContext{} = failure_context,
         %State{} = state
       ) do
    %RecordedEvent{data: data} = failed_event
    %State{idle_timeout: idle_timeout, process_manager_module: process_manager_module} = state

    Logger.error(fn ->
      describe(state) <>
        " failed to handle event " <>
        inspect(failed_event, pretty: true) <>
        " due to: " <>
        inspect(reason, pretty: true)
    end)

    case process_manager_module.error(error, data, failure_context) do
      {:retry, context} when is_map(context) ->
        # Retry the failed event
        Logger.info(fn -> describe(state) <> " is retrying failed event" end)

        process_unseen_event(failed_event, state, context)

      {:retry, delay, context} when is_map(context) and is_integer(delay) and delay >= 0 ->
        # Retry the failed event after waiting for the given delay, in milliseconds
        Logger.info(fn ->
          describe(state) <> " is retrying failed event after #{inspect(delay)}ms"
        end)

        :timer.sleep(delay)

        process_unseen_event(failed_event, state, context)

      :skip ->
        # Skip the failed event by confirming receipt
        Logger.info(fn -> describe(state) <> " is skipping event" end)

        :ok = ack_event(failed_event, state)

        {:noreply, state, idle_timeout}

      {:stop, error} ->
        # Stop the process manager instance
        Logger.warn(fn -> describe(state) <> " has requested to stop: #{inspect(error)}" end)

        {:stop, error, state}

      invalid ->
        Logger.warn(fn ->
          describe(state) <> " returned an invalid error response: #{inspect(invalid)}"
        end)

        # Stop process manager with original error
        {:stop, error, state}
    end
  end

  # update the process instance's state by applying the event
  defp mutate_state(%RecordedEvent{} = event, %State{} = state) do
    %RecordedEvent{data: data} = event

    %State{
      process_manager_module: process_manager_module,
      process_state: process_state
    } = state

    process_manager_module.apply(process_state, data)
  end

  defp dispatch_commands(commands, opts, state, last_event, context \\ %{})
  defp dispatch_commands([], _opts, _state, _last_event, _context), do: :ok

  defp dispatch_commands([command | pending_commands], opts, state, last_event, context) do
    %State{application: application} = state

    Logger.debug(fn ->
      describe(state) <> " attempting to dispatch command: " <> inspect(command)
    end)

    case Application.dispatch(application, command, opts) do
      :ok ->
        dispatch_commands(pending_commands, opts, state, last_event)

      {:error, _error} = error ->
        Logger.warn(fn ->
          describe(state) <>
            " failed to dispatch command " <> inspect(command) <> " due to: " <> inspect(error)
        end)

        failure_context = %FailureContext{
          pending_commands: pending_commands,
          process_manager_state: mutate_state(last_event, state),
          last_event: last_event,
          context: context
        }

        dispatch_failure(error, command, opts, failure_context, state)
    end
  end

  defp dispatch_failure(error, failed_command, opts, failure_context, state) do
    %State{process_manager_module: process_manager_module} = state
    %FailureContext{pending_commands: pending_commands, last_event: last_event} = failure_context

    case process_manager_module.error(error, failed_command, failure_context) do
      {:continue, commands, context} when is_list(commands) ->
        # continue dispatching the given commands
        Logger.info(fn -> describe(state) <> " is continuing with modified command(s)" end)

        dispatch_commands(commands, opts, state, last_event, context)

      {:retry, context} ->
        # retry the failed command immediately
        Logger.info(fn -> describe(state) <> " is retrying failed command" end)

        dispatch_commands([failed_command | pending_commands], opts, state, last_event, context)

      {:retry, delay, context} when is_integer(delay) ->
        # retry the failed command after waiting for the given delay, in milliseconds
        Logger.info(fn ->
          describe(state) <> " is retrying failed command after #{inspect(delay)}ms"
        end)

        :timer.sleep(delay)

        dispatch_commands([failed_command | pending_commands], opts, state, last_event, context)

      {:skip, :discard_pending} ->
        # skip the failed command and discard any pending commands
        Logger.info(fn ->
          describe(state) <>
            " is skipping event and #{length(pending_commands)} pending command(s)"
        end)

        :ok

      {:skip, :continue_pending} ->
        # skip the failed command, but continue dispatching any pending commands
        Logger.info(fn -> describe(state) <> " is ignoring error dispatching command" end)

        dispatch_commands(pending_commands, opts, state, last_event)

      {:stop, reason} = reply ->
        # stop process manager
        Logger.warn(fn -> describe(state) <> " has requested to stop: #{inspect(reason)}" end)

        reply
    end
  end

  defp describe(%State{process_manager_module: process_manager_module}),
    do: inspect(process_manager_module)

  defp persist_state(source_version, %State{} = state) do
    %State{
      application: application,
      process_manager_module: process_manager_module,
      process_state: process_state
    } = state

    snapshot = %SnapshotData{
      source_uuid: snapshot_uuid(state),
      source_version: source_version,
      source_type: Atom.to_string(process_manager_module),
      data: process_state
    }

    EventStore.record_snapshot(application, snapshot)
  end

  defp delete_state(%State{} = state) do
    %State{application: application} = state

    EventStore.delete_snapshot(application, snapshot_uuid(state))
  end

  defp ack_event(%RecordedEvent{} = event, %State{} = state) do
    %State{process_router: process_router} = state

    ProcessRouter.ack_event(process_router, event, self())
  end

  defp snapshot_uuid(%State{} = state) do
    %State{process_manager_name: process_manager_name, process_uuid: process_uuid} = state

    inspect(process_manager_name) <> "-" <> inspect(process_uuid)
  end
end
