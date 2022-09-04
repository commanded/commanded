defmodule Commanded.Aggregates.Aggregate do
  use TelemetryRegistry
  use GenServer, restart: :temporary
  use Commanded.Registration

  telemetry_event(%{
    event: [:commanded, :aggregate, :execute, :start],
    description: "Emitted when an aggregate starts executing a command",
    measurements: "%{system_time: integer()}",
    metadata: """
    %{application: Commanded.Application.t(),
      aggregate_uuid: String.t(),
      aggregate_state: struct(),
      aggregate_version: non_neg_integer(),
      caller: pid(),
      execution_context: Commanded.Aggregates.ExecutionContext.t()}
    """
  })

  telemetry_event(%{
    event: [:commanded, :aggregate, :execute, :stop],
    description: "Emitted when an aggregate stops executing a command",
    measurements: "%{duration: non_neg_integer()}",
    metadata: """
    %{application: Commanded.Application.t(),
      aggregate_uuid: String.t(),
      aggregate_state: struct(),
      aggregate_version: non_neg_integer(),
      caller: pid(),
      execution_context: Commanded.Aggregates.ExecutionContext.t(),
      events: [map()],
      error: nil | any()}
    """
  })

  telemetry_event(%{
    event: [:commanded, :aggregate, :execute, :exception],
    description: "Emitted when an aggregate raises an exception",
    measurements: "%{duration: non_neg_integer()}",
    metadata: """
    %{application: Commanded.Application.t(),
      aggregate_uuid: String.t(),
      aggregate_state: struct(),
      aggregate_version: non_neg_integer(),
      caller: pid(),
      execution_context: Commanded.Aggregates.ExecutionContext.t(),
      kind: :throw | :error | :exit,
      reason: any(),
      stacktrace: list()}
    """
  })

  @moduledoc """
  Aggregate is a `GenServer` process used to provide access to an
  instance of an event sourced aggregate.

  It allows execution of commands against an aggregate instance, and handles
  persistence of created events to the configured event store. Concurrent
  commands sent to an aggregate instance are serialized and executed in the
  order received.

  The `Commanded.Commands.Router` module will locate, or start, an aggregate
  instance when a command is dispatched. By default, an aggregate process will
  run indefinitely once started. Its lifespan may be controlled by using the
  `Commanded.Aggregates.AggregateLifespan` behaviour.

  ## Snapshotting

  You can configure state snapshots for an aggregate in config. By default
  snapshots are *not* taken for an aggregate. The following options are
  available to enable snapshots:

    - `snapshot_every` - snapshot aggregate state every so many events. Use
      `nil` to disable snapshotting, or exclude the configuration entirely.

    - `snapshot_version` - a non-negative integer indicating the version of
      the aggregate state snapshot. Incrementing this version forces any
      earlier recorded snapshots to be ignored when rebuilding aggregate
      state.

  ### Example

  In `config/config.exs` enable snapshots for `MyApp.ExampleAggregate` after
  every ten events:

      config :my_app, MyApp.Application,
        snapshotting: %{
          MyApp.ExampleAggregate => [
            snapshot_every: 10,
            snapshot_version: 1
          ]
        }

  ## Telemetry

  #{telemetry_docs()}

  """

  require Logger

  alias Commanded.Aggregate.Multi
  alias Commanded.Aggregates.Aggregate
  alias Commanded.Aggregates.AggregateStateBuilder
  alias Commanded.Aggregates.ExecutionContext
  alias Commanded.Application.Config
  alias Commanded.Event.Mapper
  alias Commanded.Event.Upcast
  alias Commanded.EventStore
  alias Commanded.EventStore.RecordedEvent
  alias Commanded.Registration
  alias Commanded.Snapshotting
  alias Commanded.Telemetry

  @type state :: struct()

  @type uuid :: String.t()

  defstruct [
    :application,
    :aggregate_module,
    :aggregate_uuid,
    :aggregate_state,
    :snapshotting,
    aggregate_version: 0,
    lifespan_timeout: :infinity
  ]

  def start_link(config, opts) do
    {start_opts, aggregate_opts} =
      Keyword.split(opts, [:debug, :name, :timeout, :spawn_opt, :hibernate_after])

    aggregate_module = Keyword.fetch!(aggregate_opts, :aggregate_module)
    aggregate_uuid = Keyword.fetch!(aggregate_opts, :aggregate_uuid)

    unless is_atom(aggregate_module),
      do: raise(ArgumentError, message: "aggregate module must be an atom")

    unless is_binary(aggregate_uuid),
      do: raise(ArgumentError, message: "aggregate identity must be a string")

    application = Keyword.fetch!(config, :application)
    snapshotting = Keyword.get(config, :snapshotting, %{})
    snapshot_options = Map.get(snapshotting, aggregate_module, [])

    state = %Aggregate{
      application: application,
      aggregate_module: aggregate_module,
      aggregate_uuid: aggregate_uuid,
      snapshotting: Snapshotting.new(application, aggregate_uuid, snapshot_options)
    }

    GenServer.start_link(__MODULE__, state, start_opts)
  end

  @doc false
  def name(application, aggregate_module, aggregate_uuid)
      when is_atom(application) and is_atom(aggregate_module) and is_binary(aggregate_uuid),
      do: {application, aggregate_module, aggregate_uuid}

  @doc """
  Execute the given command against the aggregate.

    - `aggregate_module` - the aggregate's module (e.g. `BankAccount`).
    - `aggregate_uuid` - uniquely identifies an instance of the aggregate.
    - `context` - includes command execution arguments
      (see `Commanded.Aggregates.ExecutionContext` for details).
    - `timeout` - an non-negative integer which specifies how many milliseconds
      to wait for a reply, or the atom :infinity to wait indefinitely.
      The default value is five seconds (5,000ms).

  ## Return values

  Returns `{:ok, aggregate_version, events}` on success, or `{:error, error}`
  on failure.

    - `aggregate_version` - the updated version of the aggregate after executing
       the command.
    - `events` - events produced by the command, can be an empty list.

  """
  def execute(
        application,
        aggregate_module,
        aggregate_uuid,
        %ExecutionContext{} = context,
        timeout \\ 5_000
      )
      when is_atom(aggregate_module) and is_binary(aggregate_uuid) and
             (is_number(timeout) or timeout == :infinity) do
    name = via_name(application, aggregate_module, aggregate_uuid)

    try do
      GenServer.call(name, {:execute_command, context}, timeout)
    catch
      :exit, {:noproc, {GenServer, :call, [^name, {:execute_command, ^context}, ^timeout]}} ->
        {:exit, {:normal, :aggregate_stopped}}

      :exit, {:normal, {GenServer, :call, [^name, {:execute_command, ^context}, ^timeout]}} ->
        {:exit, {:normal, :aggregate_stopped}}
    end
  end

  @doc false
  def aggregate_state(application, aggregate_module, aggregate_uuid, timeout \\ 5_000) do
    name = via_name(application, aggregate_module, aggregate_uuid)

    try do
      GenServer.call(name, :aggregate_state, timeout)
    catch
      :exit, {reason, {GenServer, :call, [^name, :aggregate_state, ^timeout]}}
      when reason in [:normal, :noproc] ->
        task =
          Task.async(fn ->
            snapshot_options =
              application
              |> Config.get(:snapshotting)
              |> Kernel.||(%{})
              |> Map.get(aggregate_module, [])

            %Aggregate{
              application: application,
              aggregate_module: aggregate_module,
              aggregate_uuid: aggregate_uuid,
              snapshotting: Snapshotting.new(application, aggregate_uuid, snapshot_options)
            }
            |> AggregateStateBuilder.populate()
            |> Map.fetch!(:aggregate_state)
          end)

        case Task.yield(task, timeout) || Task.shutdown(task) do
          {:ok, result} ->
            result

          nil ->
            exit({:timeout, {GenServer, :call, [name, :aggregate_state, timeout]}})
        end
    end
  end

  @doc false
  def aggregate_version(application, aggregate_module, aggregate_uuid, timeout \\ 5_000) do
    name = via_name(application, aggregate_module, aggregate_uuid)
    GenServer.call(name, :aggregate_version, timeout)
  end

  @doc false
  def take_snapshot(application, aggregate_module, aggregate_uuid) do
    name = via_name(application, aggregate_module, aggregate_uuid)
    GenServer.cast(name, :take_snapshot)
  end

  @doc false
  def shutdown(application, aggregate_module, aggregate_uuid) do
    name = via_name(application, aggregate_module, aggregate_uuid)
    GenServer.stop(name)
  end

  @doc false
  @impl GenServer
  def init(%Aggregate{} = state) do
    # Initial aggregate state is populated by loading its state snapshot and/or
    # events from the event store.
    {:ok, state, {:continue, :populate_aggregate_state}}
  end

  @doc false
  @impl GenServer
  def handle_continue(:populate_aggregate_state, %Aggregate{} = state) do
    state = AggregateStateBuilder.populate(state)

    # Subscribe to aggregate's events to catch any events appended to its stream
    # by another process, such as directly appended to the event store.
    {:noreply, state, {:continue, :subscribe_to_events}}
  end

  @doc false
  @impl GenServer
  def handle_continue(:subscribe_to_events, %Aggregate{} = state) do
    %Aggregate{application: application, aggregate_uuid: aggregate_uuid} = state

    :ok = EventStore.subscribe(application, aggregate_uuid)

    {:noreply, state}
  end

  @doc false
  @impl GenServer
  def handle_cast(:take_snapshot, %Aggregate{} = state), do: do_take_snapshot(state)

  @impl GenServer
  def handle_cast({:take_snapshot, lifespan_timeout}, %Aggregate{} = state) do
    do_take_snapshot(%Aggregate{state | lifespan_timeout: lifespan_timeout})
  end

  @doc false
  @impl GenServer
  def handle_call({:execute_command, %ExecutionContext{} = context}, from, %Aggregate{} = state) do
    %ExecutionContext{lifespan: lifespan, command: command} = context

    telemetry_metadata = telemetry_metadata(context, from, state)
    start_time = telemetry_start(telemetry_metadata)

    {result, state} = execute_command(context, state)

    lifespan_timeout =
      case result do
        {:ok, []} ->
          aggregate_lifespan_timeout(lifespan, :after_command, command)

        {:ok, events} ->
          aggregate_lifespan_timeout(lifespan, :after_event, events)

        {:error, error} ->
          aggregate_lifespan_timeout(lifespan, :after_error, error)

        {:error, error, _stacktrace} ->
          aggregate_lifespan_timeout(lifespan, :after_error, error)
      end

    formatted_reply = ExecutionContext.format_reply(result, context, state)

    %Aggregate{aggregate_version: aggregate_version, snapshotting: snapshotting} = state

    response =
      if Snapshotting.snapshot_required?(snapshotting, aggregate_version) do
        :ok = GenServer.cast(self(), {:take_snapshot, lifespan_timeout})

        {:reply, formatted_reply, state}
      else
        state = %Aggregate{state | lifespan_timeout: lifespan_timeout}

        case lifespan_timeout do
          {:stop, reason} -> {:stop, reason, formatted_reply, state}
          lifespan_timeout -> {:reply, formatted_reply, state, lifespan_timeout}
        end
      end

    telemetry_metadata = telemetry_metadata(context, from, state)
    telemetry_stop(start_time, telemetry_metadata, result)

    response
  end

  @doc false
  @impl GenServer
  def handle_call(:aggregate_state, _from, %Aggregate{} = state) do
    %Aggregate{aggregate_state: aggregate_state} = state

    {:reply, aggregate_state, state}
  end

  @doc false
  @impl GenServer
  def handle_call(:aggregate_version, _from, %Aggregate{} = state) do
    %Aggregate{aggregate_version: aggregate_version} = state

    {:reply, aggregate_version, state}
  end

  @doc false
  @impl GenServer
  def handle_info({:events, events}, %Aggregate{} = state) do
    %Aggregate{application: application, lifespan_timeout: lifespan_timeout} = state

    Logger.debug(describe(state) <> " received events: " <> inspect(events))

    try do
      state =
        events
        |> Enum.reject(&event_already_seen?(&1, state))
        |> Upcast.upcast_event_stream(additional_metadata: %{application: application})
        |> Enum.reduce(state, &handle_event/2)

      case lifespan_timeout do
        {:stop, reason} -> {:stop, reason, state}
        lifespan_timeout -> {:noreply, state, lifespan_timeout}
      end
    catch
      {:error, error} ->
        Logger.debug(describe(state) <> " stopping due to: " <> inspect(error))

        # Stop after event handling returned an error
        {:stop, error, state}
    end
  end

  @doc false
  @impl GenServer
  def handle_info(:timeout, %Aggregate{} = state) do
    Logger.debug(describe(state) <> " stopping due to inactivity timeout")

    {:stop, :normal, state}
  end

  defp event_already_seen?(%RecordedEvent{} = event, %Aggregate{} = state) do
    %RecordedEvent{stream_version: stream_version} = event
    %Aggregate{aggregate_version: aggregate_version} = state

    stream_version <= aggregate_version
  end

  # Handle events appended to the aggregate's stream, received by its
  # event store subscription, by applying any missed events to its state.
  defp handle_event(%RecordedEvent{} = event, %Aggregate{} = state) do
    %RecordedEvent{data: data, stream_version: stream_version} = event

    %Aggregate{
      aggregate_module: aggregate_module,
      aggregate_state: aggregate_state,
      aggregate_version: aggregate_version
    } = state

    if stream_version == aggregate_version + 1 do
      # Apply event to aggregate's state
      %Aggregate{
        state
        | aggregate_version: stream_version,
          aggregate_state: aggregate_module.apply(aggregate_state, data)
      }
    else
      Logger.debug(describe(state) <> " received an unexpected event: " <> inspect(event))

      # Throw an error when an unexpected event is received
      throw({:error, :unexpected_event_received})
    end
  end

  defp aggregate_lifespan_timeout(lifespan, function_name, args) do
    # Take the last event or the command or error
    args = args |> List.wrap() |> Enum.take(-1)

    case apply(lifespan, function_name, args) do
      timeout when timeout in [:infinity, :hibernate] ->
        timeout

      :stop ->
        {:stop, :normal}

      {:stop, _reason} = reply ->
        reply

      timeout when is_integer(timeout) and timeout >= 0 ->
        timeout

      invalid ->
        Logger.warn(
          "Invalid timeout for aggregate lifespan " <>
            inspect(lifespan) <>
            ", expected a non-negative integer, `:infinity`, `:hibernate`, `:stop`, or `{:stop, reason}` but got: " <>
            inspect(invalid)
        )

        :infinity
    end
  end

  defp before_execute_command(_aggregate_state, %ExecutionContext{before_execute: nil}), do: :ok

  defp before_execute_command(aggregate_state, %ExecutionContext{} = context) do
    %ExecutionContext{handler: handler, before_execute: before_execute} = context

    Kernel.apply(handler, before_execute, [aggregate_state, context])
  end

  defp execute_command(%ExecutionContext{} = context, %Aggregate{} = state) do
    %ExecutionContext{command: command, handler: handler, function: function} = context
    %Aggregate{aggregate_state: aggregate_state} = state

    Logger.debug(describe(state) <> " executing command: " <> inspect(command))

    with :ok <- before_execute_command(aggregate_state, context) do
      case Kernel.apply(handler, function, [aggregate_state, command]) do
        {:error, _error} = reply ->
          {reply, state}

        none when none in [:ok, nil, []] ->
          {{:ok, []}, state}

        %Multi{} = multi ->
          case Multi.run(multi) do
            {:error, _error} = reply ->
              {reply, state}

            {aggregate_state, pending_events} ->
              persist_events(pending_events, aggregate_state, context, state)
          end

        {:ok, pending_events} ->
          apply_and_persist_events(pending_events, context, state)

        pending_events ->
          apply_and_persist_events(pending_events, context, state)
      end
    else
      {:error, _error} = reply ->
        {reply, state}
    end
  rescue
    error ->
      stacktrace = __STACKTRACE__
      Logger.error(Exception.format(:error, error, stacktrace))

      {{:error, error, stacktrace}, state}
  end

  defp apply_and_persist_events(pending_events, context, %Aggregate{} = state) do
    %Aggregate{aggregate_module: aggregate_module, aggregate_state: aggregate_state} = state

    pending_events = List.wrap(pending_events)
    aggregate_state = apply_events(aggregate_module, aggregate_state, pending_events)

    persist_events(pending_events, aggregate_state, context, state)
  end

  defp apply_events(aggregate_module, aggregate_state, events) do
    Enum.reduce(events, aggregate_state, &aggregate_module.apply(&2, &1))
  end

  defp persist_events(pending_events, aggregate_state, context, %Aggregate{} = state) do
    %Aggregate{aggregate_version: expected_version} = state

    with :ok <- append_to_stream(pending_events, context, state) do
      aggregate_version = expected_version + length(pending_events)

      state = %Aggregate{
        state
        | aggregate_state: aggregate_state,
          aggregate_version: aggregate_version
      }

      {{:ok, pending_events}, state}
    else
      {:error, :wrong_expected_version} ->
        # Fetch missing events from event store
        state = AggregateStateBuilder.rebuild_from_events(state)

        # Retry command if there are any attempts left
        case ExecutionContext.retry(context) do
          {:ok, context} ->
            Logger.debug(describe(state) <> " wrong expected version, retrying command")

            execute_command(context, state)

          reply ->
            Logger.debug(describe(state) <> " wrong expected version, but not retrying command")

            {reply, state}
        end

      {:error, _error} = reply ->
        {reply, state}
    end
  end

  defp append_to_stream([], _context, _state), do: :ok

  defp append_to_stream(pending_events, %ExecutionContext{} = context, %Aggregate{} = state) do
    %Aggregate{
      application: application,
      aggregate_uuid: aggregate_uuid,
      aggregate_version: expected_version
    } = state

    %ExecutionContext{
      causation_id: causation_id,
      correlation_id: correlation_id,
      metadata: metadata
    } = context

    event_data =
      Mapper.map_to_event_data(pending_events,
        causation_id: causation_id,
        correlation_id: correlation_id,
        metadata: metadata
      )

    EventStore.append_to_stream(application, aggregate_uuid, expected_version, event_data)
  end

  defp do_take_snapshot(%Aggregate{} = state) do
    %Aggregate{
      aggregate_state: aggregate_state,
      aggregate_version: aggregate_version,
      lifespan_timeout: lifespan_timeout,
      snapshotting: snapshotting
    } = state

    Logger.debug(describe(state) <> " recording snapshot")

    state =
      case Snapshotting.take_snapshot(snapshotting, aggregate_version, aggregate_state) do
        {:ok, snapshotting} ->
          %Aggregate{state | snapshotting: snapshotting}

        {:error, error} ->
          Logger.warn(describe(state) <> " snapshot failed due to: " <> inspect(error))

          state
      end

    case lifespan_timeout do
      {:stop, reason} -> {:stop, reason, state}
      lifespan_timeout -> {:noreply, state, lifespan_timeout}
    end
  end

  defp telemetry_start(telemetry_metadata) do
    Telemetry.start([:commanded, :aggregate, :execute], telemetry_metadata)
  end

  defp telemetry_stop(start_time, telemetry_metadata, result) do
    event_prefix = [:commanded, :aggregate, :execute]

    case result do
      {:ok, events} ->
        Telemetry.stop(event_prefix, start_time, Map.put(telemetry_metadata, :events, events))

      {:error, error} ->
        Telemetry.stop(event_prefix, start_time, Map.put(telemetry_metadata, :error, error))

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

  defp telemetry_metadata(%ExecutionContext{} = context, from, %Aggregate{} = state) do
    %Aggregate{
      application: application,
      aggregate_uuid: aggregate_uuid,
      aggregate_state: aggregate_state,
      aggregate_version: aggregate_version
    } = state

    {pid, _ref} = from

    %{
      application: application,
      aggregate_uuid: aggregate_uuid,
      aggregate_state: aggregate_state,
      aggregate_version: aggregate_version,
      caller: pid,
      execution_context: context
    }
  end

  defp via_name(application, aggregate_module, aggregate_uuid) do
    name = name(application, aggregate_module, aggregate_uuid)

    Registration.via_tuple(application, name)
  end

  defp describe(%Aggregate{} = aggregate) do
    %Aggregate{
      aggregate_module: aggregate_module,
      aggregate_uuid: aggregate_uuid,
      aggregate_version: aggregate_version
    } = aggregate

    "#{inspect(aggregate_module)}<#{aggregate_uuid}@#{aggregate_version}>"
  end
end
