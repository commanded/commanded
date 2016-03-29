defmodule Commanded.Entities.Entity do
  @moduledoc """
  Entity process to provide access to a single event sourced entity.

  Allows execution of commands against and entity and handles persistence of events to the event store.
  """

  use GenServer

  def start_link(entity_module, entity_id) do
    GenServer.start_link(__MODULE__, {entity_module, entity_module.new(entity_id)})
  end

  def init({entity_module, entity_state}) do
    GenServer.cast(self, {:load_events, entity_module})
    {:ok, entity_state}
  end

  @doc """
  Execute the given command against the entity
  """
  def execute(server, command, handler) do
    GenServer.call(server, {:execute_command, command, handler})
  end

  @doc """
  Load any existing events for the entity from storage and repopulate the state using those events
  """
  def handle_cast({:load_events, entity_module}, %{id: id} = state) do
    # TODO: deserialize each event.payload

    state = case EventStore.read_stream_forward(id) do
      {:ok, events} -> entity_module.load(id, events)
      {:error, :stream_not_found} -> state
    end

    {:noreply, state}
  end

  @doc """
  Execute the given command, using the provided handler, against the current entity state
  """
  def handle_call({:execute_command, command, handler}, _from, %{version: version} = state) do
    expected_version = version

    state =
      state
      |> handler.handle(command)
      |> persist_events(expected_version)

    {:reply, :ok, state}
  end

  defp persist_events(%{id: id, events: events} = state, expected_version) do
    # TODO: serialize each event.payload
    event_data = map_to_event_data(events)

    case EventStore.append_to_stream(id, expected_version, event_data) do
      {:ok, _events} -> %{state | events: []}
      {:error, :wrong_expected_version} -> state # TODO: retry
    end
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
end
