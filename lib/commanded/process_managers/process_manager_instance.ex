defmodule Commanded.ProcessManagers.ProcessManagerInstance do
  @moduledoc false

  use GenServer, restart: :temporary

  require Logger

  alias Commanded.Application
  alias Commanded.EventStore
  alias Commanded.EventStore.{RecordedEvent, SnapshotData}
  alias Commanded.ProcessManagers.{FailureContext, ProcessRouter}
  alias Commanded.Telemetry

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
    if event_already_seen?(event, state) do
      process_seen_event(event, state)
    else
      process_unseen_event(event, state)
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
    telemetry_metadata = telemetry_metadata(event, state)
    start_time = telemetry_start(telemetry_metadata)

    case handle_event(event, state) do
      {:error, error} ->
        handle_process_unseen_event_error(
          error,
          start_time,
          telemetry_metadata,
          event,
          state,
          context
        )

      {:error, error, stacktrace} ->
        handle_process_unseen_event_error(
          error,
          start_time,
          telemetry_metadata,
          stacktrace,
          event,
          state,
          context
        )

      commands ->
        do_process_unseen_event(event, start_time, telemetry_metadata, state, context, commands)
    end
  end

  defp handle_process_unseen_event_error(
         error,
         start_time,
         telemetry_metadata,
         stacktrace \\ nil,
         event,
         state,
         context
       ) do
    failure_context = %FailureContext{
      context: context,
      last_event: event,
      process_manager_state: state,
      stacktrace: stacktrace
    }

    if is_nil(stacktrace),
      do: telemetry_stop(start_time, telemetry_metadata, {:error, error}),
      else: telemetry_stop(start_time, telemetry_metadata, {:error, error, stacktrace})

    handle_event_error({:error, error}, event, failure_context, state)
  end

  defp do_process_unseen_event(event, start_time, telemetry_metadata, state, context, commands) do
    %RecordedEvent{
      correlation_id: correlation_id,
      event_id: event_id
    } = event

    commands = List.wrap(commands)

    # Copy event id, as causation id, and correlation id from handled event.
    opts = [causation_id: event_id, correlation_id: correlation_id, returning: false]

    case dispatch_commands(commands, opts, state, event) do
      :ok ->
        telemetry_stop(start_time, telemetry_metadata, {:ok, commands})
        do_mutate_event_state(event, state, context, commands)

      {:stop, reason} ->
        telemetry_stop(start_time, telemetry_metadata, {:error, reason})

        {:stop, reason, state}
    end
  end

  defp do_mutate_event_state(
         %RecordedEvent{event_number: event_number} = event,
         state,
         context,
         commands
       ) do
    case mutate_state(event, state) do
      {:error, error, stacktrace} ->
        failure_context = %FailureContext{
          context: context,
          last_event: event,
          process_manager_state: state,
          stacktrace: stacktrace
        }

        handle_event_error({:error, error}, event, failure_context, state)

      process_state ->
        state = %State{
          state
          | process_state: process_state,
            last_seen_event: event_number
        }

        :ok = persist_state(event_number, state)
        :ok = ack_event(event, state)

        handle_after_command(commands, state)
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

    error
    |> process_manager_module.error(data, failure_context)
    |> log_handle_event_error_response(state)
    |> maybe_apply_delay()
    |> do_handle_event_error(failed_event, state, idle_timeout, reason)
  end

  defp log_handle_event_error_response({:retry, _} = reply, state) do
    Logger.info(fn -> describe(state) <> " is retrying failed event" end)

    reply
  end

  defp log_handle_event_error_response({:retry, delay, _} = reply, state)
       when is_integer(delay) and delay >= 0 do
    Logger.info(fn ->
      describe(state) <> " is retrying failed event after #{inspect(delay)}ms"
    end)

    reply
  end

  defp log_handle_event_error_response(:skip, state) do
    Logger.info(fn -> describe(state) <> " is skipping event" end)

    :skip
  end

  defp log_handle_event_error_response({:stop, reason} = reply, state) do
    Logger.warn(fn -> describe(state) <> " has requested to stop: #{inspect(reason)}" end)

    reply
  end

  defp log_handle_event_error_response(invalid, state) do
    Logger.warn(fn ->
      describe(state) <> " returned an invalid error response: #{inspect(invalid)}"
    end)

    invalid
  end

  # Retry the failed event
  defp do_handle_event_error(
         {:retry, %FailureContext{context: context}},
         failed_event,
         state,
         _,
         _
       ) do
    process_unseen_event(failed_event, state, context)
  end

  # Retry the failed event
  defp do_handle_event_error({:retry, context}, failed_event, state, _, _) do
    process_unseen_event(failed_event, state, context)
  end

  # Retry the failed event after waiting for the given delay (milliseconds)
  defp do_handle_event_error(
         {:retry, delay, %FailureContext{context: context}},
         failed_event,
         state,
         _,
         _
       )
       when is_map(context) and is_integer(delay) and delay >= 0 do
    process_unseen_event(failed_event, state, context)
  end

  # Retry the failed event after waiting for the given delay (milliseconds)
  defp do_handle_event_error({:retry, delay, context}, failed_event, state, _, _)
       when is_map(context) and is_integer(delay) and delay >= 0 do
    process_unseen_event(failed_event, state, context)
  end

  # Skip the failed event by confirming receipt
  defp do_handle_event_error(:skip, failed_event, state, idle_timeout, _) do
    :ok = ack_event(failed_event, state)

    {:noreply, state, idle_timeout}
  end

  # Stop process manager with received stop reason
  defp do_handle_event_error({:error, reason}, _, state, _, _) do
    {:stop, reason, state}
  end

  # Stop process manager with original error reason
  defp do_handle_event_error(_, _, state, _, reason) do
    {:stop, reason, state}
  end

  defp handle_after_command([], %State{} = state) do
    %State{idle_timeout: idle_timeout} = state

    {:noreply, state, idle_timeout}
  end

  defp handle_after_command([command | commands], %State{} = state) do
    %State{
      process_manager_module: process_manager_module,
      process_state: process_state
    } = state

    case process_manager_module.after_command(process_state, command) do
      :stop ->
        Logger.debug(fn ->
          describe(state) <> " has been stopped by command " <> inspect(command)
        end)

        :ok = delete_state(state)

        {:stop, :normal, state}

      _ ->
        handle_after_command(commands, state)
    end
  end

  # Update the process instance's state by applying the event.
  defp mutate_state(%RecordedEvent{} = event, %State{} = state) do
    %RecordedEvent{data: data} = event

    %State{
      process_manager_module: process_manager_module,
      process_state: process_state
    } = state

    try do
      process_manager_module.apply(process_state, data)
    rescue
      error ->
        stacktrace = __STACKTRACE__
        Logger.error(fn -> Exception.format(:error, error, stacktrace) end)

        {:error, error, stacktrace}
    end
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

        process_manager_state =
          case mutate_state(last_event, state) do
            {:error, _, _} -> state
            process_manager_state -> process_manager_state
          end

        failure_context = %FailureContext{
          pending_commands: pending_commands,
          process_manager_state: process_manager_state,
          last_event: last_event,
          context: context
        }

        dispatch_failure(error, command, opts, failure_context, state)
    end
  end

  defp dispatch_failure({:error, reason} = error, failed_command, opts, failure_context, state) do
    %State{process_manager_module: process_manager_module} = state
    %FailureContext{pending_commands: pending_commands, last_event: last_event} = failure_context
    commands = [failed_command | pending_commands]

    error
    |> process_manager_module.error(failed_command, failure_context)
    |> log_dispatch_failure_response(state, failure_context)
    |> maybe_apply_delay()
    |> do_handle_dispatch_failure(commands, opts, state, last_event, reason)
  end

  defp log_dispatch_failure_response({:continue, _, _} = reply, state, _) do
    Logger.info(fn -> describe(state) <> " is continuing with modified command(s)" end)

    reply
  end

  defp log_dispatch_failure_response({:retry, _} = reply, state, _) do
    Logger.info(fn -> describe(state) <> " is retrying failed command" end)

    reply
  end

  defp log_dispatch_failure_response({:retry, delay, _} = reply, state, _)
       when is_integer(delay) and delay >= 0 do
    Logger.info(fn ->
      describe(state) <> " is retrying failed command after #{inspect(delay)}ms"
    end)

    reply
  end

  defp log_dispatch_failure_response(:skip, state, _) do
    Logger.info(fn -> describe(state) <> " is ignoring error dispatching command" end)

    :skip
  end

  defp log_dispatch_failure_response({:skip, :continue_pending} = reply, state, _) do
    Logger.info(fn -> describe(state) <> " is ignoring error dispatching command" end)

    reply
  end

  defp log_dispatch_failure_response({:skip, :pending_commands} = reply, state, %FailureContext{
         pending_commands: pending_commands
       }) do
    Logger.info(fn ->
      describe(state) <> " is skipping event and #{length(pending_commands)} pending command(s)"
    end)

    reply
  end

  defp log_dispatch_failure_response({:stop, reason} = reply, state, _) do
    Logger.warn(fn -> describe(state) <> " has requested to stop: #{inspect(reason)}" end)

    reply
  end

  defp log_dispatch_failure_response(invalid, state, _) do
    Logger.warn(fn ->
      describe(state) <> " returned an invalid error response: #{inspect(invalid)}"
    end)

    invalid
  end

  defp maybe_apply_delay({:retry, delay, _} = reply) when is_integer(delay) and delay >= 0 do
    :timer.sleep(delay)

    reply
  end

  defp maybe_apply_delay(reply), do: reply

  # Continue dispatching the given commands
  defp do_handle_dispatch_failure(
         {:continue, commands, %FailureContext{context: context}},
         _,
         opts,
         state,
         last_event,
         _
       )
       when is_list(commands) and is_map(context) do
    dispatch_commands(commands, opts, state, last_event, context)
  end

  # Continue dispatching the given commands
  defp do_handle_dispatch_failure({:continue, commands, context}, _, opts, state, last_event, _)
       when is_list(commands) and is_map(context) do
    dispatch_commands(commands, opts, state, last_event, context)
  end

  # Retry the failed command immediately
  defp do_handle_dispatch_failure(
         {:retry, %FailureContext{context: context}},
         commands,
         opts,
         state,
         last_event,
         _
       )
       when is_map(context) do
    dispatch_commands(commands, opts, state, last_event, context)
  end

  # Retry the failed command immediately
  defp do_handle_dispatch_failure({:retry, context}, commands, opts, state, last_event, _)
       when is_map(context) do
    dispatch_commands(commands, opts, state, last_event, context)
  end

  # Retry the failed command after waiting for the given delay, in milliseconds
  defp do_handle_dispatch_failure(
         {:retry, _, %FailureContext{context: context}},
         commands,
         opts,
         state,
         last_event,
         _
       )
       when is_map(context) do
    dispatch_commands(commands, opts, state, last_event, context)
  end

  # Retry the failed command after waiting for the given delay, in milliseconds
  defp do_handle_dispatch_failure({:retry, _, context}, commands, opts, state, last_event, _)
       when is_map(context) do
    dispatch_commands(commands, opts, state, last_event, context)
  end

  # Skip the failed command, but continue dispatching any pending commands
  defp do_handle_dispatch_failure(:skip, [_ | pending_commands], opts, state, last_event, _) do
    dispatch_commands(pending_commands, opts, state, last_event)
  end

  # Skip the failed command, but continue dispatching any pending commands
  defp do_handle_dispatch_failure(
         {:skip, :continue_pending},
         [_ | pending_commands],
         opts,
         state,
         last_event,
         _
       ) do
    dispatch_commands(pending_commands, opts, state, last_event)
  end

  # Skip the failed command and discard any pending commands
  defp do_handle_dispatch_failure({:skip, :discard_pending}, _, _, _, _, _), do: :ok

  # Stop process manager with received stop reason
  defp do_handle_dispatch_failure({:stop, reason}, _, _, _, _, _) do
    {:stop, reason}
  end

  # Stop process manager with original error reason
  defp do_handle_dispatch_failure(_, _, _, _, _, reason), do: {:stop, reason}

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

  defp telemetry_start(telemetry_metadata) do
    Telemetry.start([:commanded, :process_manager, :handle], telemetry_metadata)
  end

  defp telemetry_stop(start_time, telemetry_metadata, handle_result) do
    event_prefix = [:commanded, :process_manager, :handle]

    case handle_result do
      {:ok, commands} ->
        telemetry_metadata =
          telemetry_metadata |> Map.put(:commands, commands) |> Map.put(:error, nil)

        Telemetry.stop(event_prefix, start_time, telemetry_metadata)

      {:error, error} ->
        telemetry_metadata =
          telemetry_metadata
          |> Map.put(:error, error)
          |> Map.put_new(:commands, [])

        Telemetry.stop(event_prefix, start_time, telemetry_metadata)

      {:error, error, stacktrace} ->
        Telemetry.exception(
          event_prefix,
          start_time,
          :error,
          error,
          stacktrace,
          telemetry_metadata
        )
    end
  end

  defp telemetry_metadata(%RecordedEvent{} = event, %State{} = state) do
    %State{
      application: application,
      process_manager_name: process_manager_name,
      process_manager_module: process_manager_module,
      process_state: process_state,
      process_uuid: process_uuid
    } = state

    %{
      application: application,
      process_manager_name: process_manager_name,
      process_manager_module: process_manager_module,
      process_state: process_state,
      process_uuid: process_uuid,
      recorded_event: event
    }
  end
end
