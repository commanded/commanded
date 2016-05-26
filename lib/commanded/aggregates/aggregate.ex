defmodule Commanded.Aggregates.Aggregate do
  @moduledoc """
  Process to provide access to a single event sourced aggregate root.

  Allows execution of commands against an aggregate and handles persistence of events to the event store.
  """
  use GenServer
  require Logger

  alias Commanded.Event.Serializer

  @command_retries 3

  def start_link(aggregate_module, aggregate_id) do
    GenServer.start_link(__MODULE__, {aggregate_module, aggregate_id})
  end

  def init({aggregate_module, aggregate_id}) do
    # initial state is populated by loading events from event store
    GenServer.cast(self, {:load_events, aggregate_module, aggregate_id})

    {:ok, nil}
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
  def state(server) do
    GenServer.call(server, {:state})
  end

  @doc """
  Load any existing events for the aggregate from storage and repopulate the state using those events
  """
  def handle_cast({:load_events, aggregate_module, aggregate_id}, nil) do
    state = load_events(aggregate_module, aggregate_id)

    {:noreply, state}
  end

  @doc """
  Execute the given command, using the provided handler, against the current aggregate state
  """
  def handle_call({:execute_command, command, handler}, _from, state) do
    state = execute_command(command, handler, state, @command_retries)

    {:reply, :ok, state}
  end

  def handle_call({:state}, _from, state) do
    {:reply, state, state}
  end

  # load events from the event store and create the aggregate
  defp load_events(aggregate_module, aggregate_id) do
    state = case EventStore.read_stream_forward(aggregate_id) do
      {:ok, events} -> aggregate_module.load(aggregate_id, map_from_recorded_events(events))
      {:error, :stream_not_found} -> aggregate_module.new(aggregate_id)
    end

    # events list should only include uncommitted events
    %{state | pending_events: []}
  end

  defp execute_command(command, handler, %{uuid: uuid, version: version} = state, retries) when retries > 0 do
    expected_version = version

    state = handler.handle(state, command)

    case persist_events(state, expected_version) do
      {:ok, _events} -> %{state | pending_events: []}
      {:error, :wrong_expected_version} ->
        Logger.error("failed to persist events for aggregate #{uuid} due to wrong expected version")

        # reload aggregate's events
        state = load_events(state.__struct__, uuid)

        # retry command
        execute_command(command, handler, state, retries - 1)
    end
  end

  defp persist_events(%{pending_events: []}, _expected_version) do
    # no pending events to persist, do nothing
    {:ok, []}
  end

  defp persist_events(%{uuid: uuid, pending_events: pending_events}, expected_version) do
    correlation_id = UUID.uuid4
    event_data = Serializer.map_to_event_data(pending_events, correlation_id)

    EventStore.append_to_stream(uuid, expected_version, event_data)
  end

  defp map_from_recorded_events(recorded_events) when is_list(recorded_events) do
    Serializer.map_from_recorded_events(recorded_events)
  end
end
