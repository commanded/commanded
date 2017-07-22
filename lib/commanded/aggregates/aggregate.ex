defmodule Commanded.Aggregates.Aggregate do
  @moduledoc """
  Process to provide access to a single event sourced aggregate root.

  Allows execution of commands against an aggregate and handles persistence of events to the event store.
  """

  use GenServer
  use Commanded.EventStore

  require Logger

  alias Commanded.Aggregates.Aggregate
  alias Commanded.Event.Mapper

  @registry_provider Application.get_env(:commanded, :registry_provider, Registry)
  @aggregate_registry_name :aggregate_registry
  @read_event_batch_size 100

  defstruct [
    aggregate_module: nil,
    aggregate_uuid: nil,
    aggregate_state: nil,
    aggregate_version: 0,
  ]

  defmodule DefaultLifespan do
    @behaviour Commanded.Aggregates.AggregateLifespan

    def after_command(_), do: :infinity
  end

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
  Execute the given command against the aggregate, optionally providing a timeout.
  - `timeout` is an integer greater than zero which specifies how many milliseconds to wait for a reply, or the atom :infinity to wait indefinitely.
    The default value is 5000.

  Returns `:ok` on success, or `{:error, reason}` on failure
  """
  def execute(aggregate_uuid, command, handler, function \\ :execute, timeout \\ 5_000, lifespan \\ DefaultLifespan) do
    GenServer.call(via_tuple(aggregate_uuid), {:execute_command, handler, function, command, lifespan}, timeout)
  end

  @doc """
  Access the aggregate's state
  """
  def aggregate_state(aggregate_uuid), do: GenServer.call(via_tuple(aggregate_uuid), {:aggregate_state})
  def aggregate_state(aggregate_uuid, timeout), do: GenServer.call(via_tuple(aggregate_uuid), {:aggregate_state}, timeout)

  @doc """
  Access the aggregate's version
  """
  def aggregate_version(aggregate_uuid), do: GenServer.call(via_tuple(aggregate_uuid), {:aggregate_version})

  @doc """
  Load any existing events for the aggregate from storage and repopulate the state using those events
  """
  def handle_cast({:populate_aggregate_state}, %Aggregate{} = state) do
    state = populate_aggregate_state(state)

    {:noreply, state}
  end

  @doc """
  Execute the given command, using the provided handler, against the current aggregate state
  """
  def handle_call({:execute_command, handler, function, command, lifespan}, _from, %Aggregate{} = state) do
    {reply, state} = execute_command(handler, function, command, state)

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

  defp populate_aggregate_state(%Aggregate{aggregate_module: aggregate_module} = state) do
    rebuild_from_events(%Aggregate{state |
      aggregate_version: 0,
      aggregate_state: struct(aggregate_module)
    })
  end

  # load events from the event store, in batches, to rebuild the aggregate state
  defp rebuild_from_events(%Aggregate{aggregate_uuid: aggregate_uuid, aggregate_module: aggregate_module} = state) do
    case @event_store.stream_forward(aggregate_uuid, 0, @read_event_batch_size) do
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

  defp execute_command(handler, function, command, %Aggregate{aggregate_uuid: aggregate_uuid, aggregate_version: expected_version, aggregate_state: aggregate_state, aggregate_module: aggregate_module} = state) do
    case Kernel.apply(handler, function, [aggregate_state, command]) do
      {:error, _reason} = reply -> {reply, state}
      nil -> {:ok, state}
      [] -> {:ok, state}
      events ->
        pending_events = List.wrap(events)

        updated_state = apply_events(aggregate_module, aggregate_state, pending_events)

        {:ok, stream_version} = persist_events(pending_events, aggregate_uuid, expected_version)

        state = %Aggregate{state |
          aggregate_state: updated_state,
          aggregate_version: stream_version
        }

        {:ok, state}
    end
  end

  defp apply_events(aggregate_module, aggregate_state, events) do
    Enum.reduce(events, aggregate_state, &aggregate_module.apply(&2, &1))
  end

  defp persist_events([], _aggregate_uuid, expected_version), do: {:ok, expected_version}
  defp persist_events(pending_events, aggregate_uuid, expected_version) do
    correlation_id = UUID.uuid4
    event_data = Mapper.map_to_event_data(pending_events, correlation_id)

    @event_store.append_to_stream(aggregate_uuid, expected_version, event_data)
  end
end
