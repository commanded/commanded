defmodule Commanded.Entities.Entity do
  @moduledoc """
  Entity process to provide access to a single event sourced entity.

  Allows execution of commands against and entity and handles persistence of events to the event store.
  """

  use GenServer

  def start_link(entity_module, id) do
    GenServer.start_link(__MODULE__, entity_module, entity_module.new(id))
  end

  def init(entity_module, state) do
    GenServer.cast(self, {:load_events, entity_module})
    {:ok, state}
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
  def handle_call({:execute_command, command, handler}, _from, state) do
    state =
      state
      |> handler.handle(command)
      |> persist_events

    {:reply, :ok, state}
  end

  defp persist_events(%{id: id, events: events, version: version} = state) do
    # TODO: serialize each event.payload

    case EventStore.append_to_stream(id, version, events) do
      {:ok, _events} -> %{state | events: []}
      {:error, :wrong_expected_version} -> state # TODO: retry
    end
  end
end
