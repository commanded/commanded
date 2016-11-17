defmodule Commanded.Aggregates.Aggregate do
  @moduledoc """
  Process to provide access to a single event sourced aggregate root.

  Allows execution of commands against an aggregate and handles persistence of events to the event store.
  """
  use GenServer
  require Logger

  alias Commanded.Aggregates.Aggregate
  alias Commanded.Event.Mapper

  @read_event_batch_size 100

  defstruct [
    aggregate_module: nil,
    aggregate_uuid: nil,
    aggregate_state: nil,
    aggregate_version: 0,
  ]

  def start_link(aggregate_module, aggregate_uuid) do
    GenServer.start_link(__MODULE__, %Aggregate{
      aggregate_module: aggregate_module,
      aggregate_uuid: aggregate_uuid
    })
  end

  def init(%Aggregate{} = state) do
    # initial aggregate state is populated by loading events from event store
    GenServer.cast(self, {:populate_aggregate_state})

    {:ok, state}
  end

  @doc """
  Execute the given command against the aggregate, optionally providing a timeout.
  - `timeout` is an integer greater than zero which specifies how many milliseconds to wait for a reply, or the atom :infinity to wait indefinitely.
    The default value is 5000.

  Returns `:ok` on success, or `{:error, reason}` on failure
  """
  def execute(server, command, handler, timeout \\ 5_000) do
    GenServer.call(server, {:execute_command, command, handler}, timeout)
  end

  @doc """
  Access the aggregate's state
  """
  def aggregate_state(server) do
    GenServer.call(server, {:aggregate_state})
  end

  def aggregate_state(server, timeout) do
    GenServer.call(server, {:aggregate_state}, timeout)
  end

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
  def handle_call({:execute_command, command, handler}, _from, %Aggregate{} = state) do
    {reply, state} = execute_command(command, handler, state)

    {:reply, reply, state}
  end

  def handle_call({:aggregate_state}, _from, %Aggregate{aggregate_state: aggregate_state} = state) do
    {:reply, aggregate_state, state}
  end

  defp populate_aggregate_state(%Aggregate{aggregate_module: aggregate_module, aggregate_uuid: aggregate_uuid} = state) do
    aggregate_state = case load_events(state) do
      {:ok, events} ->
        # fetched all events, load aggregate
        load_aggregate(aggregate_module, map_from_recorded_events(events))

      {:error, :stream_not_found} ->
        # aggregate does not exist so create new
        struct(aggregate_module)
    end

    %Aggregate{state | aggregate_state: aggregate_state}
  end

  # rebuild the aggregate's state from the given events applied to its empty state
  defp load_aggregate(aggregate_module, events) do
    apply_events(aggregate_module, struct(aggregate_module), events)
  end

  defp load_events(%Aggregate{} = state), do: load_events(state, 1, [])

  # load events from the event store, in batches of 100 events, and create the aggregate
  defp load_events(%Aggregate{aggregate_uuid: aggregate_uuid} = state, start_version, events) do
    case EventStore.read_stream_forward(aggregate_uuid, start_version, @read_event_batch_size) do
      {:ok, batch} when length(batch) < @read_event_batch_size ->
        {:ok, events ++ batch}

      {:ok, batch} ->
        next_version = start_version + @read_event_batch_size

        # fetch next batch of events
        load_events(state, next_version, events ++ batch)

      {:error, :stream_not_found} = reply -> reply
    end
  end

  defp execute_command(command, handler, %Aggregate{aggregate_uuid: aggregate_uuid, aggregate_version: expected_version, aggregate_state: aggregate_state, aggregate_module: aggregate_module} = state) do
    pending_events = execute_command(handler, aggregate_state, command)

    updated_state = apply_events(aggregate_module, aggregate_state, pending_events)

    :ok = persist_events(pending_events, aggregate_uuid, expected_version)

    {:ok, %Aggregate{state | aggregate_state: updated_state}}
  end

  defp execute_command(handler, aggregate_state, command) do
    aggregate_state
    |> handler.handle(command)
    |> List.wrap
  end

  defp apply_events(aggregate_module, aggregate_state, events) do
    Enum.reduce(events, aggregate_state, &aggregate_module.apply(&2, &1))
  end

  defp persist_events([], _aggregate_uuid, _expected_version), do: :ok
  defp persist_events(pending_events, aggregate_uuid, expected_version) do
    correlation_id = UUID.uuid4
    event_data = Mapper.map_to_event_data(pending_events, correlation_id)

    :ok = EventStore.append_to_stream(aggregate_uuid, expected_version, event_data)
  end

  defp map_from_recorded_events(recorded_events), do: Mapper.map_from_recorded_events(recorded_events)
end
