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

      config :commanded, ExampleAggregate
        snapshot_every: 10,
        snapshot_version: 1
  """

  use GenServer
  use Commanded.Registration

  require Logger

  alias Commanded.Aggregates.{Aggregate,ExecutionContext}
  alias Commanded.Event.Mapper
  alias Commanded.EventStore
  alias Commanded.EventStore.SnapshotData

  @read_event_batch_size 100

  defstruct [
    aggregate_module: nil,
    aggregate_uuid: nil,
    aggregate_state: nil,
    aggregate_version: 0,
    snapshot_every: nil,
    snapshot_module_version: 1,
    snapshot_version: 0,
  ]

  def start_link(aggregate_module, aggregate_uuid, opts \\ []) do
    snapshot_options = snapshot_options(aggregate_module)

    aggregate = %Aggregate{
      aggregate_module: aggregate_module,
      aggregate_uuid: aggregate_uuid,
      snapshot_every: Keyword.get(snapshot_options, :snapshot_every),
      snapshot_module_version: Keyword.get(snapshot_options, :snapshot_version, 1),
    }

    GenServer.start_link(__MODULE__, aggregate, opts)
  end


  @doc false
  def name(aggregate_module, aggregate_uuid),
    do: {aggregate_module, aggregate_uuid}

  def init(%Aggregate{} = state) do
    # initial aggregate state is populated by loading state snapshot and/or
    # events from event store
    GenServer.cast(self(), :populate_aggregate_state)

    {:ok, state}
  end

  @doc """
  Execute the given command against the aggregate.

    - `aggregate_module` - the aggregate's module (e.g. `BankAccount`).
    - `aggregate_uuid` - uniquely identifies an instance of the aggregate.
    - `context` - includes command execution arguments
      (see `Commanded.Aggregates.ExecutionContext` for details).
    - `timeout` - an integer greater than zero which specifies how many
      milliseconds to wait for a reply, or the atom :infinity to wait
      indefinitely. The default value is five seconds (5,000ms).

  ## Return values

  Returns `{:ok, aggregate_version, events}` on success, or `{:error, reason}`
  on failure.

    - `aggregate_version` - the updated version of the aggregate after executing
       the command.
    - `events` - events produced by the command, can be an empty list.

  """
  def execute(aggregate_module, aggregate_uuid, %ExecutionContext{} = context, timeout \\ 5_000) do
    GenServer.call(via_name(aggregate_module, aggregate_uuid), {:execute_command, context}, timeout)
  end

  @doc false
  def aggregate_state(aggregate_module, aggregate_uuid, timeout \\ 5_000)
  def aggregate_state(aggregate_module, aggregate_uuid, timeout) do
    GenServer.call(via_name(aggregate_module, aggregate_uuid), :aggregate_state, timeout)
  end

  @doc false
  def aggregate_version(aggregate_module, aggregate_uuid) do
    GenServer.call(via_name(aggregate_module, aggregate_uuid), :aggregate_version)
  end

  @doc false
  def shutdown(aggregate_module, aggregate_uuid) do
    GenServer.stop(via_name(aggregate_module, aggregate_uuid))
  end

  @doc false
  def handle_cast(:populate_aggregate_state, %Aggregate{} = state) do
    {:noreply, populate_aggregate_state(state)}
  end

  def handle_cast({:snapshot_state, lifespan}, %Aggregate{} = state) do
    {:noreply, do_snapshot(state), lifespan}
  end

  @doc false
  def handle_call({:execute_command, %ExecutionContext{} = context}, _from, %Aggregate{} = state) do
    {reply, state} = execute_command(context, state)

    timeout = aggregate_lifespan_timeout(context)

    if snapshotting_enabled?(state) && snapshot_required?(state) do
      GenServer.cast(self(), {:snapshot_state, timeout})
    end

    {:reply, reply, state, timeout}
  end

  @doc false
  def handle_call(:aggregate_state, _from, %Aggregate{aggregate_state: aggregate_state} = state) do
    {:reply, aggregate_state, state}
  end

  @doc false
  def handle_call(:aggregate_version, _from, %Aggregate{aggregate_version: aggregate_version} = state) do
    {:reply, aggregate_version, state}
  end

  @doc false
  def handle_info(:timeout, %Aggregate{} = state) do
    {:stop, :normal, state}
  end

  # Attempt to fetch a snapshot for the aggregate to use as its initial state.
  # If the snapshot exists, fetch any subsequent events to rebuild its state.
  # Otherwise start with the aggregate struct and stream all existing events for
  # the aggregate from the event store to rebuild its state from those events.
  defp populate_aggregate_state(%Aggregate{aggregate_module: aggregate_module, aggregate_uuid: aggregate_uuid} = state) do
    aggregate =
      with true <- snapshotting_enabled?(state),
           {:ok, snapshot} <- EventStore.read_snapshot(aggregate_uuid),
           true <- snapshot_valid?(snapshot, state) do
        # populate initial state from snapshot
        %Aggregate{state |
          aggregate_version: snapshot.source_version,
          aggregate_state: snapshot.data
        }
      else
        _ ->
          # no snapshot (or outdated), use intial empty state
          %Aggregate{state |
            aggregate_version: 0,
            aggregate_state: struct(aggregate_module)
          }
      end

    rebuild_from_events(aggregate)
  end

  # Load events from the event store, in batches, to rebuild the aggregate state
  defp rebuild_from_events(%Aggregate{aggregate_module: aggregate_module, aggregate_uuid: aggregate_uuid, aggregate_version: aggregate_version} = state) do
    case EventStore.stream_forward(aggregate_uuid, aggregate_version + 1, @read_event_batch_size) do
      {:error, :stream_not_found} ->
        # aggregate does not exist so return initial state
        state

      event_stream ->
        # rebuild aggregate state from event stream
        event_stream
        |> Stream.map(fn event ->
          {event.data, event.stream_version}
        end)
        |> Stream.transform(state, fn ({event, stream_version}, state) ->
          case event do
            nil -> {:halt, state}
            event ->
              state = %Aggregate{state |
                aggregate_version: stream_version,
                aggregate_state: aggregate_module.apply(state.aggregate_state, event),
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
  end

  defp aggregate_lifespan_timeout(%ExecutionContext{command: command, lifespan: lifespan}) do
    case lifespan.after_command(command) do
      :infinity -> :infinity
      :hibernate -> :hibernate
      timeout when is_integer(timeout) and timeout >= 0 -> timeout
      invalid ->
        Logger.warn(fn -> "Invalid timeout for aggregate lifespan #{inspect lifespan}, expected a non-negative integer, `:infinity`, or `:hibernate` but got: #{inspect invalid}" end)
        :infinity
    end
  end

  # is snapshotting configured for the aggregate?
  defp snapshotting_enabled?(%Aggregate{snapshot_every: snapshot_every}),
    do: is_number(snapshot_every) && snapshot_every > 0

  # was the snapshot taken at the current version?
  defp snapshot_valid?(%SnapshotData{metadata: metadata}, %Aggregate{snapshot_module_version: expected_version}) do
    Map.get(metadata, "snapshot_version", 1) == expected_version
  end

  # do snapshot aggregate state
  defp snapshot_required?(%Aggregate{aggregate_version: aggregate_version, snapshot_every: snapshot_every, snapshot_version: snapshot_version})
    when aggregate_version - snapshot_version >= snapshot_every, do: true

  # not yet enough events to snapshot
  defp snapshot_required?(_state), do: false

  # snapshot aggregate state
  defp do_snapshot(%Aggregate{} = state) do
    %Aggregate{
      aggregate_module: aggregate_module,
      aggregate_uuid: aggregate_uuid,
      aggregate_version: aggregate_version,
      aggregate_state: aggregate_state,
    } = state

    snapshot = %SnapshotData{
      source_uuid: aggregate_uuid,
      source_version: aggregate_version,
      source_type: Atom.to_string(aggregate_module),
      data: aggregate_state,
      metadata: %{"snapshot_version" => aggregate_version}
    }

    Logger.debug(fn -> "Recording snapshot of aggregate state for: #{inspect aggregate_uuid}@#{aggregate_version} (#{inspect aggregate_module})" end)

    :ok = EventStore.record_snapshot(snapshot)

    %Aggregate{state | snapshot_version: aggregate_version}
  end

  defp execute_command(
    %ExecutionContext{handler: handler, function: function, command: command} = context,
    %Aggregate{aggregate_module: aggregate_module, aggregate_version: expected_version, aggregate_state: aggregate_state} = state)
  do
    case Kernel.apply(handler, function, [aggregate_state, command]) do
      {:error, _reason} = reply ->
        {reply, state}

      none when none in [nil, []] ->
        {{:ok, expected_version, []}, state}

      %Commanded.Aggregate.Multi{} = multi ->
        case Commanded.Aggregate.Multi.run(multi) do
          {:error, _reason} = reply ->
            {reply, state}

          {aggregate_state, pending_events} ->
            persist_events(pending_events, aggregate_state, context, state)
        end

      events ->
        pending_events = List.wrap(events)
        aggregate_state = apply_events(aggregate_module, aggregate_state, pending_events)

        persist_events(pending_events, aggregate_state, context, state)
    end
  end

  defp apply_events(aggregate_module, aggregate_state, events) do
    Enum.reduce(events, aggregate_state, &aggregate_module.apply(&2, &1))
  end

  defp persist_events(pending_events, aggregate_state, context, %Aggregate{aggregate_uuid: aggregate_uuid, aggregate_version: expected_version} = state) do
    with {:ok, stream_version} <- append_to_stream(pending_events, aggregate_uuid, expected_version, context) do
      state = %Aggregate{state |
        aggregate_state: aggregate_state,
        aggregate_version: stream_version,
      }

      {{:ok, stream_version, pending_events}, state}
    else
      {:error, _reason} = reply -> {reply, state}
    end
  end

  defp append_to_stream([], _stream_uuid, expected_version, _context), do: {:ok, expected_version}
  defp append_to_stream(pending_events, stream_uuid, expected_version, %ExecutionContext{causation_id: causation_id, correlation_id: correlation_id, metadata: metadata}) do
    event_data = Mapper.map_to_event_data(pending_events, causation_id, correlation_id, metadata)

    EventStore.append_to_stream(stream_uuid, expected_version, event_data)
  end

  # get the snapshot options for the aggregate defined in environment config.
  defp snapshot_options(aggregate_module),
    do: Application.get_env(:commanded, aggregate_module, [])

  defp via_name(aggregate_module, aggregate_uuid),
    do: name(aggregate_module, aggregate_uuid) |> via_tuple()
end
