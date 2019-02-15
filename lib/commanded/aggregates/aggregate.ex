defmodule Commanded.Aggregates.Aggregate do
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

  In `config/config.exs` enable snapshots for `ExampleAggregate` after every ten
  events:

      config :commanded, ExampleAggregate,
        snapshot_every: 10,
        snapshot_version: 1

  """

  use GenServer, restart: :temporary
  use Commanded.Registration

  require Logger

  alias Commanded.Aggregates.{Aggregate, ExecutionContext}
  alias Commanded.Event.Mapper
  alias Commanded.EventStore
  alias Commanded.EventStore.{RecordedEvent, SnapshotData}
  alias Commanded.Snapshotting

  @read_event_batch_size 100

  defstruct [
    :aggregate_module,
    :aggregate_uuid,
    :aggregate_state,
    :snapshotting,
    aggregate_version: 0,
    lifespan_timeout: :infinity
  ]

  def start_link([aggregate_module, aggregate_uuid, opts])
      when is_atom(aggregate_module) and is_binary(aggregate_uuid) do
    aggregate = %Aggregate{
      aggregate_module: aggregate_module,
      aggregate_uuid: aggregate_uuid,
      snapshotting: Snapshotting.new(aggregate_uuid, snapshot_options(aggregate_module))
    }

    GenServer.start_link(__MODULE__, aggregate, opts)
  end

  @doc false
  def name(aggregate_module, aggregate_uuid)
      when is_atom(aggregate_module) and is_binary(aggregate_uuid),
      do: {aggregate_module, aggregate_uuid}

  @doc false
  def init(%Aggregate{} = state) do
    # Initial aggregate state is populated by loading its state snapshot and/or
    # events from the event store.
    :ok = GenServer.cast(self(), :populate_aggregate_state)

    # Subscribe to aggregate's events to catch any events appended to its stream
    # by another process, such as directly appended to the event store.
    :ok = GenServer.cast(self(), :subscribe_to_events)

    {:ok, state}
  end

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
  def execute(aggregate_module, aggregate_uuid, %ExecutionContext{} = context, timeout \\ 5_000)
      when is_atom(aggregate_module) and is_binary(aggregate_uuid) and
             (is_number(timeout) or timeout == :infinity) do
    GenServer.call(
      via_name(aggregate_module, aggregate_uuid),
      {:execute_command, context},
      timeout
    )
  end

  @doc false
  def aggregate_state(aggregate_module, aggregate_uuid, timeout \\ 5_000) do
    GenServer.call(via_name(aggregate_module, aggregate_uuid), :aggregate_state, timeout)
  end

  @doc false
  def aggregate_version(aggregate_module, aggregate_uuid, timeout \\ 5_000) do
    GenServer.call(via_name(aggregate_module, aggregate_uuid), :aggregate_version, timeout)
  end

  @doc false
  def take_snapshot(aggregate_module, aggregate_uuid) do
    GenServer.cast(via_name(aggregate_module, aggregate_uuid), :take_snapshot)
  end

  @doc false
  def shutdown(aggregate_module, aggregate_uuid) do
    GenServer.stop(via_name(aggregate_module, aggregate_uuid))
  end

  @doc false
  def handle_cast(:populate_aggregate_state, %Aggregate{} = state) do
    {:noreply, populate_aggregate_state(state)}
  end

  @doc false
  def handle_cast(:subscribe_to_events, %Aggregate{} = state) do
    %Aggregate{aggregate_uuid: aggregate_uuid} = state

    :ok = EventStore.subscribe(aggregate_uuid)

    {:noreply, state}
  end

  @doc false
  def handle_cast(:take_snapshot, %Aggregate{} = state) do
    %Aggregate{
      aggregate_state: aggregate_state,
      aggregate_version: aggregate_version,
      lifespan_timeout: lifespan_timeout,
      snapshotting: snapshotting
    } = state

    Logger.debug(fn -> describe(state) <> " recording snapshot" end)

    state =
      case Snapshotting.take_snapshot(snapshotting, aggregate_version, aggregate_state) do
        {:ok, snapshotting} ->
          %Aggregate{state | snapshotting: snapshotting}

        {:error, error} ->
          Logger.warn(fn -> describe(state) <> " snapshot failed due to: " <> inspect(error) end)

          state
      end

    case lifespan_timeout do
      :stop ->
        {:stop, :normal, state}

      lifespan_timeout ->
        {:noreply, state, lifespan_timeout}
    end
  end

  @doc false
  def handle_call({:execute_command, %ExecutionContext{} = context}, _from, %Aggregate{} = state) do
    %ExecutionContext{lifespan: lifespan, command: command} = context

    {reply, state} = execute_command(context, state)

    lifespan_timeout =
      case reply do
        {:ok, _stream_version, []} ->
          aggregate_lifespan_timeout(lifespan, :after_command, command)

        {:ok, _stream_version, events} ->
          aggregate_lifespan_timeout(lifespan, :after_event, events)

        {:error, error} ->
          aggregate_lifespan_timeout(lifespan, :after_error, error)
      end

    state = %Aggregate{state | lifespan_timeout: lifespan_timeout}

    %Aggregate{aggregate_version: aggregate_version, snapshotting: snapshotting} = state

    if Snapshotting.snapshot_required?(snapshotting, aggregate_version) do
      :ok = GenServer.cast(self(), :take_snapshot)

      {:reply, reply, state}
    else
      case lifespan_timeout do
        :stop -> {:stop, :normal, reply, state}
        lifespan_timeout -> {:reply, reply, state, lifespan_timeout}
      end
    end
  end

  @doc false
  def handle_call(:aggregate_state, _from, %Aggregate{} = state) do
    %Aggregate{aggregate_state: aggregate_state} = state

    {:reply, aggregate_state, state}
  end

  @doc false
  def handle_call(:aggregate_version, _from, %Aggregate{} = state) do
    %Aggregate{aggregate_version: aggregate_version} = state

    {:reply, aggregate_version, state}
  end

  @doc false
  def handle_info({:events, events}, %Aggregate{} = state) do
    %Aggregate{lifespan_timeout: lifespan_timeout} = state

    Logger.debug(fn -> describe(state) <> " received events: #{inspect(events)}" end)

    try do
      state = Enum.reduce(events, state, &handle_event/2)

      {:noreply, state, lifespan_timeout}
    catch
      {:error, error} ->
        Logger.debug(fn -> describe(state) <> " stopping due to: #{inspect(error)}" end)

        # Stop after event handling returned an error
        {:stop, error, state}
    end
  end

  @doc false
  def handle_info(:timeout, %Aggregate{} = state) do
    Logger.debug(fn -> describe(state) <> " stopping due to inactivity timeout" end)

    {:stop, :normal, state}
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

    expected_version = aggregate_version + 1

    case stream_version do
      ^expected_version ->
        # apply event to aggregate's state
        %Aggregate{
          state
          | aggregate_version: stream_version,
            aggregate_state: aggregate_module.apply(aggregate_state, data)
        }

      already_seen_version when already_seen_version <= aggregate_version ->
        # ignore events already applied to aggregate state
        state

      _unexpected_version ->
        Logger.debug(fn ->
          describe(state) <> " received an unexpected event: #{inspect(event)}"
        end)

        # throw an error when an unexpected event is received
        throw({:error, :unexpected_event_received})
    end
  end

  # Populate the aggregate's state from a snapshot, if present, and it's events.
  #
  # Attempt to fetch a snapshot for the aggregate to use as its initial state.
  # If the snapshot exists, fetch any subsequent events to rebuild its state.
  # Otherwise start with the aggregate struct and stream all existing events for
  # the aggregate from the event store to rebuild its state from those events.
  defp populate_aggregate_state(%Aggregate{} = state) do
    %Aggregate{aggregate_module: aggregate_module, snapshotting: snapshotting} = state

    aggregate =
      case Snapshotting.read_snapshot(snapshotting) do
        {:ok, %SnapshotData{source_version: source_version, data: data}} ->
          %Aggregate{
            state
            | aggregate_version: source_version,
              aggregate_state: data
          }

        {:error, _error} ->
          # No snapshot present, or exists but for outdated state, so use intial empty state
          %Aggregate{state | aggregate_version: 0, aggregate_state: struct(aggregate_module)}
      end

    rebuild_from_events(aggregate)
  end

  # Load events from the event store, in batches, to rebuild the aggregate state
  defp rebuild_from_events(%Aggregate{} = state) do
    %Aggregate{aggregate_uuid: aggregate_uuid, aggregate_version: aggregate_version} = state

    case EventStore.stream_forward(aggregate_uuid, aggregate_version + 1, @read_event_batch_size) do
      {:error, :stream_not_found} ->
        # aggregate does not exist, return initial state
        state

      event_stream ->
        rebuild_from_event_stream(event_stream, state)
    end
  end

  # Rebuild aggregate state from a `Stream` of its events
  defp rebuild_from_event_stream(event_stream, %Aggregate{} = state) do
    %Aggregate{aggregate_module: aggregate_module} = state

    event_stream
    |> Stream.map(fn event ->
      {event.data, event.stream_version}
    end)
    |> Stream.transform(state, fn {event, stream_version}, state ->
      case event do
        nil ->
          {:halt, state}

        event ->
          state = %Aggregate{
            state
            | aggregate_version: stream_version,
              aggregate_state: aggregate_module.apply(state.aggregate_state, event)
          }

          {[state], state}
      end
    end)
    |> Stream.take(-1)
    |> Enum.at(0)
    |> case do
      nil -> state
      state -> state
    end
  end

  defp aggregate_lifespan_timeout(lifespan, timeout_function_name, args) do
    # Take the last event or the command/error
    args = args |> List.wrap() |> Enum.take(-1)

    case apply(lifespan, timeout_function_name, args) do
      timeout when timeout in [:infinity, :hibernate, :stop] ->
        timeout

      timeout when is_integer(timeout) and timeout >= 0 ->
        timeout

      invalid ->
        Logger.warn(fn ->
          "Invalid timeout for aggregate lifespan " <>
            inspect(lifespan) <>
            ", expected a non-negative integer, `:infinity`, `:hibernate`, or `:stop` but got: " <>
            inspect(invalid)
        end)

        :infinity
    end
  end

  defp execute_command(%ExecutionContext{retry_attempts: retry_attempts}, %Aggregate{} = state)
       when retry_attempts < 0,
       do: {{:error, :too_many_attempts}, state}

  defp execute_command(%ExecutionContext{} = context, %Aggregate{} = state) do
    %ExecutionContext{
      command: command,
      handler: handler,
      function: function,
      retry_attempts: retry_attempts
    } = context

    %Aggregate{
      aggregate_module: aggregate_module,
      aggregate_version: expected_version,
      aggregate_state: aggregate_state
    } = state

    Logger.debug(fn -> describe(state) <> " executing command: #{inspect(command)}" end)

    {reply, state} =
      case Kernel.apply(handler, function, [aggregate_state, command]) do
        {:error, _error} = reply ->
          {reply, state}

        none when none in [nil, []] ->
          {{:ok, expected_version, []}, state}

        %Commanded.Aggregate.Multi{} = multi ->
          case Commanded.Aggregate.Multi.run(multi) do
            {:error, _error} = reply ->
              {reply, state}

            {aggregate_state, pending_events} ->
              persist_events(pending_events, aggregate_state, context, state)
          end

        events ->
          pending_events = List.wrap(events)
          aggregate_state = apply_events(aggregate_module, aggregate_state, pending_events)

          persist_events(pending_events, aggregate_state, context, state)
      end

    case reply do
      {:error, :wrong_expected_version} ->
        Logger.debug(fn -> describe(state) <> " wrong expected version, retrying command" end)

        # fetch missing events from event store
        state = rebuild_from_events(state)

        # retry command, but decrement retry attempts (to prevent infinite retries)
        execute_command(%ExecutionContext{context | retry_attempts: retry_attempts - 1}, state)

      reply ->
        {reply, state}
    end
  end

  defp apply_events(aggregate_module, aggregate_state, events) do
    Enum.reduce(events, aggregate_state, &aggregate_module.apply(&2, &1))
  end

  defp persist_events(pending_events, aggregate_state, context, %Aggregate{} = state) do
    %Aggregate{aggregate_uuid: aggregate_uuid, aggregate_version: expected_version} = state

    with :ok <- append_to_stream(pending_events, aggregate_uuid, expected_version, context) do
      aggregate_version = expected_version + length(pending_events)

      state = %Aggregate{
        state
        | aggregate_state: aggregate_state,
          aggregate_version: aggregate_version
      }

      {{:ok, aggregate_version, pending_events}, state}
    else
      {:error, _error} = reply ->
        {reply, state}
    end
  end

  defp append_to_stream([], _stream_uuid, _expected_version, _context), do: :ok

  defp append_to_stream(pending_events, stream_uuid, expected_version, context) do
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

    EventStore.append_to_stream(stream_uuid, expected_version, event_data)
  end

  # get the snapshot options for the aggregate defined in environment config.
  defp snapshot_options(aggregate_module),
    do: Application.get_env(:commanded, aggregate_module, [])

  defp via_name(aggregate_module, aggregate_uuid),
    do: name(aggregate_module, aggregate_uuid) |> via_tuple()

  defp describe(%Aggregate{} = aggregate) do
    %Aggregate{
      aggregate_module: aggregate_module,
      aggregate_uuid: aggregate_uuid,
      aggregate_version: aggregate_version
    } = aggregate

    "#{inspect(aggregate_module)}<#{aggregate_uuid}@#{aggregate_version}>"
  end
end
