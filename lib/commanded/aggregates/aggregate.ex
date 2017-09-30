defmodule Commanded.Aggregates.Aggregate do
  @moduledoc """
  Aggregate is a `GenServer` process used to provide access to an instance of an event sourced aggregate root.
  It allows execution of commands against an aggregate instance, and handles persistence of events to the configured event store.

  Concurrent commands sent to an aggregate instance are serialized and executed in the order received.

  The `Commanded.Commands.Router` module will locate, or start, an aggregate instance when a command is dispatched.
  By default, it will run indefinitely once started. Its lifespan may be controlled by using the `Commanded.Aggregates.AggregateLifespan` behaviour.
  """

  use GenServer

  require Logger

  alias Commanded.Aggregates.{Aggregate,DefaultLifespan}
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
  ]

  def start_link(aggregate_module, aggregate_uuid) do
    name = via_tuple(aggregate_uuid)
    GenServer.start_link(__MODULE__, %Aggregate{
      aggregate_module: aggregate_module,
      aggregate_uuid: aggregate_uuid
    },
    name: name)
  end

  defp via_tuple(aggregate_uuid) do
    {:via, @registry_provider, {@aggregate_registry_name, aggregate_uuid}}
  end

  def init(%Aggregate{} = state) do
    # initial aggregate state is populated by loading events from event store
    GenServer.cast(self(), {:populate_aggregate_state})

    {:ok, state}
  end

  @doc """
  Execute the given command against the aggregate, optionally providing a timeout and lifespan.

  - `aggregate_uuid` uniquely identifies an instance of the aggregate.

  - `command` is the command to execute, typically a struct (e.g. `%OpenBankAccount{...}`).

  - `metadata` is the metadata that is attached to the command.

  - `handler` is the module that handles the command.
    It may be the aggregate module, but does not have to be as you can specify and use a command handler module.

  - `function` is the name of function, as an atom, that handles the command.
    The default value is `:execute`, used to support command dispatch directly to the aggregate module.

  - `timeout` is an integer greater than zero which specifies how many milliseconds to wait for a reply, or the atom :infinity to wait indefinitely.
    The default value is 5000.

  - `lifespan` is a module implementing the `Commanded.Aggregates.AggregateLifespan` behaviour to control the aggregate instance process lifespan.
    The default value, `Commanded.Aggregates.DefaultLifespan`, keeps the process running indefinitely.

  Returns `{:ok, aggregate_version}` on success, or `{:error, reason}` on failure.
  """
  def execute(aggregate_uuid, command, metadata, handler, function \\ :execute, timeout \\ 5_000, lifespan \\ DefaultLifespan) do
    GenServer.call(via_tuple(aggregate_uuid), {:execute_command, metadata, handler, function, command, lifespan}, timeout)
  end

  @doc false
  def aggregate_state(aggregate_uuid), do: GenServer.call(via_tuple(aggregate_uuid), {:aggregate_state})

  @doc false
  def aggregate_state(aggregate_uuid, timeout), do: GenServer.call(via_tuple(aggregate_uuid), {:aggregate_state}, timeout)

  @doc false
  def aggregate_version(aggregate_uuid), do: GenServer.call(via_tuple(aggregate_uuid), {:aggregate_version})

  @doc false
  def handle_cast({:populate_aggregate_state}, %Aggregate{} = state) do
    state = populate_aggregate_state(state)

    {:noreply, state}
  end

  @doc false
  def handle_call({:execute_command, metadata, handler, function, command, lifespan}, _from, %Aggregate{} = state) do
    {reply, state} = execute_command(metadata, handler, function, command, state)

    {:reply, reply, state, lifespan.after_command(command)}
  end

  def handle_call({:aggregate_state}, _from, %Aggregate{aggregate_state: aggregate_state} = state) do
    {:reply, aggregate_state, state}
  end

  def handle_call({:aggregate_version}, _from, %Aggregate{aggregate_version: aggregate_version} = state) do
    {:reply, aggregate_version, state}
  end

  def handle_info(:timeout, %Aggregate{} = state) do
    {:stop, :normal, state}
  end

  # Load any existing events for the aggregate from storage and repopulate the state using those events
  defp populate_aggregate_state(%Aggregate{aggregate_module: aggregate_module} = state) do
    rebuild_from_events(%Aggregate{state |
      aggregate_version: 0,
      aggregate_state: struct(aggregate_module)
    })
  end

  # Load events from the event store, in batches, to rebuild the aggregate state
  defp rebuild_from_events(%Aggregate{aggregate_uuid: aggregate_uuid, aggregate_module: aggregate_module} = state) do
    case EventStore.stream_forward(aggregate_uuid, 0, @read_event_batch_size) do
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

  defp execute_command(metadata, handler, function, command, %Aggregate{aggregate_uuid: aggregate_uuid, aggregate_version: expected_version, aggregate_state: aggregate_state, aggregate_module: aggregate_module} = state) do
    case Kernel.apply(handler, function, [aggregate_state, command]) do
      {:error, _reason} = reply -> {reply, state}
      events ->
        pending_events = List.wrap(events)

        updated_state = apply_events(aggregate_module, aggregate_state, pending_events)

        {:ok, stream_version} = persist_events(pending_events, aggregate_uuid, expected_version, metadata)

        state = %Aggregate{state |
          aggregate_state: updated_state,
          aggregate_version: stream_version
        }

        {{:ok, stream_version}, state}
    end
  end

  defp apply_events(aggregate_module, aggregate_state, events) do
    Enum.reduce(events, aggregate_state, &aggregate_module.apply(&2, &1))
  end

  defp persist_events([], _aggregate_uuid, expected_version, _metadata), do: {:ok, expected_version}
  defp persist_events(pending_events, aggregate_uuid, expected_version, metadata) do
    correlation_id = UUID.uuid4
    event_data = Mapper.map_to_event_data(pending_events, correlation_id, nil, metadata)

    EventStore.append_to_stream(aggregate_uuid, expected_version, event_data)
  end
end
