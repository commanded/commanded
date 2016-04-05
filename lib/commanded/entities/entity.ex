defmodule Commanded.Entities.Entity do
  @moduledoc """
  Entity process to provide access to a single event sourced entity.

  Allows execution of commands against an entity and handles persistence of events to the event store.
  """
  use GenServer
  require Logger

  @command_retries 3

  def start_link(entity_module, entity_id) do
    GenServer.start_link(__MODULE__, {entity_module, entity_id})
  end

  def init({entity_module, entity_id}) do
    # initial state is populated by loading events from event store
    GenServer.cast(self, {:load_events, entity_module, entity_id})

    {:ok, nil}
  end

  @doc """
  Execute the given command against the entity
  """
  def execute(server, command, handler) do
    GenServer.call(server, {:execute_command, command, handler})
  end

  @doc """
  Access the entity's state
  """
  def state(server) do
    GenServer.call(server, {:state})
  end

  @doc """
  Load any existing events for the entity from storage and repopulate the state using those events
  """
  def handle_cast({:load_events, entity_module, entity_id}, nil) do
    state = load_events(entity_module, entity_id)

    {:noreply, state}
  end

  @doc """
  Execute the given command, using the provided handler, against the current entity state
  """
  def handle_call({:execute_command, command, handler}, _from, %{id: id, version: version} = state) do
    state = execute_command(command, handler, state, @command_retries)

    {:reply, :ok, state}
  end

  def handle_call({:state}, _from, state) do
    {:reply, state, state}
  end

  # load events from the event store and create the entity
  defp load_events(entity_module, entity_id) do
    state = case EventStore.read_stream_forward(entity_id) do
      {:ok, events} -> entity_module.load(entity_id, map_from_recorded_event(events))
      {:error, :stream_not_found} -> entity_module.new(entity_id)
    end

    # events list should only include uncommitted events
    state = %{state | events: []}
  end

  defp execute_command(command, handler, %{id: id, version: version} = state, retries) when retries > 0 do
    expected_version = version

    state = handler.handle(state, command)

    case persist_events(state, expected_version) do
      {:ok, _events} -> %{state | events: []}
      {:error, :wrong_expected_version} ->
        Logger.error("failed to persist events for entity #{id} due to wrong expected version")

        # reload entity's events
        state = load_events(state.__struct__, id)

        # retry command
        execute_command(command, handler, state, retries - 1)
    end
  end

  defp persist_events(%{id: id, events: events} = state, expected_version) do
    event_data = map_to_event_data(events)

    EventStore.append_to_stream(id, expected_version, event_data)
  end

  defp map_from_recorded_event(recorded_events) when is_list(recorded_events) do
    Enum.map(recorded_events, &map_from_recorded_event/1)
  end

  defp map_from_recorded_event(recorded_event) do
    type =
      recorded_event.event_type
      |> String.to_atom
      |> struct

    deserialize_payload(recorded_event.payload, type)
  end

  defp deserialize_payload(payload, type) do
    Poison.decode!(payload, as: type)
  end

  defp map_to_event_data(events) when is_list(events) do
    correlation_id = UUID.uuid4

    Enum.map(events, &map_to_event_data(&1, correlation_id))
  end

  defp map_to_event_data(event, correlation_id) do
    %EventStore.EventData{
      correlation_id: correlation_id,
      event_type: Atom.to_string(event.__struct__),
      headers: nil,
      payload: serialize_event(event)
    }
  end

  defp serialize_event(event) do
    Poison.encode!(event)
  end

  defp raise_error(error_message) do
    Logger.error(error_message)
    exit error_message
  end
end
