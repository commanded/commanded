defmodule Commanded.Aggregates.Aggregate do
  @moduledoc """
  Process to provide access to a single event sourced aggregate root.

  Allows execution of commands against an aggregate and handles persistence of events to the event store.
  """
  use GenServer
  require Logger

  alias Commanded.Aggregates.Aggregate
  alias Commanded.Event.Mapper

  defstruct aggregate_module: nil, aggregate_uuid: nil, aggregate_state: nil

  def start_link(aggregate_module, aggregate_uuid) do
    GenServer.start_link(__MODULE__, %Aggregate{
      aggregate_module: aggregate_module,
      aggregate_uuid: aggregate_uuid
    })
  end

  def init(%Aggregate{} = state) do
    # initial aggregate state is populated by loading events from event store
    GenServer.cast(self, {:load_events})

    {:ok, state}
  end

  @doc """
  Execute the given command against the aggregate
  """
  def execute(server, command, handler) do
    GenServer.call(server, {:execute_command, command, handler})
  end

  @doc """
  Access the aggregate's state
  """
  def aggregate_state(server) do
    GenServer.call(server, {:aggregate_state})
  end

  @doc """
  Load any existing events for the aggregate from storage and repopulate the state using those events
  """
  def handle_cast({:load_events}, %Aggregate{} = state) do
    state = load_events(state)

    {:noreply, state}
  end

  @doc """
  Execute the given command, using the provided handler, against the current aggregate state
  """
  def handle_call({:execute_command, command, handler}, _from, state) do
    {reply, state} = execute_command(command, handler, state)

    {:reply, reply, state}
  end

  def handle_call({:aggregate_state}, _from, %Aggregate{aggregate_state: aggregate_state} = state) do
    {:reply, aggregate_state, state}
  end

  # load events from the event store and create the aggregate
  defp load_events(%Aggregate{aggregate_module: aggregate_module, aggregate_uuid: aggregate_uuid} = state) do
    aggregate_state = case EventStore.read_stream_forward(aggregate_uuid) do
      {:ok, events} -> aggregate_module.load(aggregate_uuid, map_from_recorded_events(events))
      {:error, :stream_not_found} -> aggregate_module.new(aggregate_uuid)
    end

    # events list should only include uncommitted events
    aggregate_state = %{aggregate_state | pending_events: []}

    %Aggregate{state | aggregate_state: aggregate_state}
  end

  defp execute_command(command, handler, %Aggregate{aggregate_state: %{version: version} = aggregate_state} = state) do
    expected_version = version

    with {:ok, aggregate_state} <- handle_command(handler, aggregate_state, command),
         {:ok, aggregate_state} <- persist_events(aggregate_state, expected_version)
      do {:ok, %Aggregate{state | aggregate_state: aggregate_state}}
    else
      {:error, reason} = reply ->
        Logger.warn(fn -> "failed to handle command due to: #{inspect reason}" end)
        {reply, state}
    end
  end

  defp handle_command(handler, aggregate_state, command) do
    case handler.handle(aggregate_state, command) do
      {:error, _reason} = reply -> reply
      aggregate_state -> {:ok, aggregate_state}
    end
  end

  # no pending events to persist, do nothing
  defp persist_events(%{pending_events: []} = aggregate_state, _expected_version), do: {:ok, aggregate_state}

  defp persist_events(%{uuid: aggregate_uuid, pending_events: pending_events} = aggregate_state, expected_version) do
    correlation_id = UUID.uuid4
    event_data = Mapper.map_to_event_data(pending_events, correlation_id)

    :ok = EventStore.append_to_stream(aggregate_uuid, expected_version, event_data)

    # clear pending events after appending to stream
    {:ok, %{aggregate_state | pending_events: []}}
  end

  defp map_from_recorded_events(recorded_events) when is_list(recorded_events) do
    Mapper.map_from_recorded_events(recorded_events)
  end
end
