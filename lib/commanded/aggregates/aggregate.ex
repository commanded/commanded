defmodule Commanded.Aggregates.Aggregate do
  @moduledoc """
  Aggregate is a `GenServer` process used to provide access to an
  instance of an event sourced aggregate root. It allows execution of commands
  against an aggregate instance, and handles persistence of created events to
  the configured event store.

  Concurrent commands sent to an aggregate instance are serialized and executed
  in the order received.

  The `Commanded.Commands.Router` module will locate, or start, an aggregate
  instance when a command is dispatched. By default, an aggregate process will
  run indefinitely once started. Its lifespan may be controlled by using the
  `Commanded.Aggregates.AggregateLifespan` behaviour.
  """

  use GenServer

  require Logger

  alias Commanded.Aggregates.{Aggregate,ExecutionContext}
  alias Commanded.Event.Mapper
  alias Commanded.EventStore

  @registry_provider Application.get_env(:commanded, :registry_provider, Registry)
  @aggregate_registry_name :aggregate_registry
  @read_event_batch_size 100

  defstruct [
    aggregate_module: nil,
    aggregate_uuid: nil,
    aggregate_state: nil,
    aggregate_version: 0,
    identity_prefix: nil,
  ]

  def start_link(aggregate_module, aggregate_uuid, identity_prefix \\ nil)
  def start_link(aggregate_module, aggregate_uuid, identity_prefix) do
    name = via_tuple(aggregate_module, aggregate_uuid)

    GenServer.start_link(__MODULE__, %Aggregate{
      aggregate_module: aggregate_module,
      aggregate_uuid: aggregate_uuid,
      identity_prefix: identity_prefix,
    },
    name: name)
  end

  defp via_tuple(aggregate_module, aggregate_uuid) do
    {:via, @registry_provider, {@aggregate_registry_name, {aggregate_module, aggregate_uuid}}}
  end

  @doc false
  def init(%Aggregate{} = state) do
    # initial aggregate state is populated by loading events from event store
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
    milliseconds to wait for a reply, or the atom :infinity to wait indefinitely.
    The default value is five seconds (5,000ms).

  ## Return values

  Returns `{:ok, aggregate_version, event_count, events}` on success, or `{:error, reason}` on failure.

    - `aggregate_version` - the updated version of the aggregate after executing the command.
    - `event_count` - number of events produced by the command, will be 0 when no events created.
    - `events` - events produced by the command, can be empty.

  """
  def execute(aggregate_module, aggregate_uuid, %ExecutionContext{} = context, timeout \\ 5_000) do
    GenServer.call(via_tuple(aggregate_module, aggregate_uuid), {:execute_command, context}, timeout)
  end

  @doc false
  def aggregate_state(aggregate_module, aggregate_uuid) do
    GenServer.call(via_tuple(aggregate_module, aggregate_uuid), :aggregate_state)
  end

  @doc false
  def aggregate_state(aggregate_module, aggregate_uuid, timeout) do
    GenServer.call(via_tuple(aggregate_module, aggregate_uuid), :aggregate_state, timeout)
  end

  @doc false
  def aggregate_version(aggregate_module, aggregate_uuid) do
    GenServer.call(via_tuple(aggregate_module, aggregate_uuid), :aggregate_version)
  end

  @doc false
  def handle_cast(:populate_aggregate_state, %Aggregate{} = state) do
    {:noreply, populate_aggregate_state(state)}
  end

  @doc false
  def handle_call({:execute_command, %ExecutionContext{command: command, lifespan: lifespan} = context}, _from, %Aggregate{} = state) do
    {reply, state} = execute_command(context, state)

    {:reply, reply, state, lifespan.after_command(command)}
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

  # Load any existing events for the aggregate from storage and repopulate the state using those events
  defp populate_aggregate_state(%Aggregate{aggregate_module: aggregate_module} = state) do
    aggregate = %Aggregate{state |
      aggregate_version: 0,
      aggregate_state: struct(aggregate_module)
    }

    rebuild_from_events(aggregate)
  end

  # Load events from the event store, in batches, to rebuild the aggregate state
  defp rebuild_from_events(%Aggregate{aggregate_module: aggregate_module} = state) do
    case EventStore.stream_forward(stream_uuid(state), 0, @read_event_batch_size) do
      {:error, :stream_not_found} ->
        # aggregate does not exist so return empty state
        state

      event_stream ->
        # rebuild aggregate state from event stream
        event_stream
        |> Stream.map(fn event ->
          {Mapper.map_from_recorded_event(event), event.stream_version}
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

  defp execute_command(
    %ExecutionContext{handler: handler, function: function, command: command, metadata: metadata},
    %Aggregate{aggregate_module: aggregate_module, aggregate_version: expected_version, aggregate_state: aggregate_state} = state)
  do
    case Kernel.apply(handler, function, [aggregate_state, command]) do
      {:error, _reason} = reply ->
        {reply, state}

      none when none in [nil, []] ->
        {{:ok, expected_version, 0, []}, state}

      events ->
        pending_events = List.wrap(events)

        updated_state = apply_events(aggregate_module, aggregate_state, pending_events)

        {:ok, stream_version} = persist_events(pending_events, stream_uuid(state), expected_version, metadata)

        state = %Aggregate{state |
          aggregate_state: updated_state,
          aggregate_version: stream_version
        }

        {{:ok, stream_version, length(pending_events), pending_events}, state}
    end
  end

  defp apply_events(aggregate_module, aggregate_state, events) do
    Enum.reduce(events, aggregate_state, &aggregate_module.apply(&2, &1))
  end

  defp persist_events([], _stream_uuid, expected_version, _metadata), do: {:ok, expected_version}
  defp persist_events(pending_events, stream_uuid, expected_version, metadata) do
    correlation_id = UUID.uuid4()
    event_data = Mapper.map_to_event_data(pending_events, correlation_id, nil, metadata)

    EventStore.append_to_stream(stream_uuid, expected_version, event_data)
  end

  # Get the stream indentity to read/append events for the aggregate, with an optional prefix
  defp stream_uuid(%Aggregate{aggregate_uuid: aggregate_uuid, identity_prefix: nil}), do: aggregate_uuid
  defp stream_uuid(%Aggregate{aggregate_uuid: aggregate_uuid, identity_prefix: identity_prefix}), do: identity_prefix <> aggregate_uuid
end
