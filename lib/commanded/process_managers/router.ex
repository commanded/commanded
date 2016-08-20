defmodule Commanded.ProcessManagers.Router do
  @moduledoc """
  Router is responsible for starting, continuing and completing process mansgers in response to events.
  """

  use GenServer
  require Logger

  alias Commanded.ProcessManagers.Supervisor
  alias Commanded.ProcessManagers.{ProcessManager,Router}
  alias Commanded.Event.Serializer

  defstruct process_manager_name: nil, process_manager_module: nil, command_dispatcher: nil, process_managers: %{}, supervisor: nil, last_seen_event_id: nil

  def start_link(process_manager_name, process_manager_module, command_dispatcher) do
    GenServer.start_link(__MODULE__, %Router{
      process_manager_name: process_manager_name,
      process_manager_module: process_manager_module,
      command_dispatcher: command_dispatcher
    })
  end

  def init(%Router{command_dispatcher: command_dispatcher} = state) do
    {:ok, supervisor} = Supervisor.start_link(command_dispatcher)

    state = %Router{state | supervisor: supervisor}

    GenServer.cast(self, {:subscribe_to_events})

    {:ok, state}
  end

  def handle_cast({:subscribe_to_events}, %Router{process_manager_name: process_manager_name} = state) do
    {:ok, _} = EventStore.subscribe_to_all_streams(process_manager_name, self)
    {:noreply, state}
  end

  def handle_info({:events, events}, %Router{process_manager_name: process_manager_name} = state) do
    Logger.debug("process manager router \"#{process_manager_name}\" received events: #{inspect events}")

    state =
      events
      |> Enum.filter(fn event -> !already_seen_event?(event, state) end)
      |> Enum.map(&Serializer.map_from_recorded_event/1)
      |> Enum.reduce(state, fn (event, state) -> handle_event(event, state) end)

    state = %Router{state | last_seen_event_id: List.last(events).event_id}

    {:noreply, state}
  end

  def handle_info({:DOWN, _ref, :process, pid, reason}, %Router{process_managers: process_managers} = state) do
    Logger.warn(fn -> "process manager process down due to: #{reason}" end)

    {:noreply, %Router{state | process_managers: remove_process_manager(process_managers, pid)}}
  end

  # ignore already seen event
  defp already_seen_event?(%EventStore.RecordedEvent{event_id: event_id} = event, %Router{last_seen_event_id: last_seen_event_id}) when not is_nil(last_seen_event_id) and event_id <= last_seen_event_id do
    Logger.debug("process manager has already seen event: #{inspect event}")
    true
  end
  defp already_seen_event?(_event, _state), do: false

  defp handle_event(event, %Router{process_manager_module: process_manager_module, process_managers: process_managers, supervisor: supervisor} = state) do
    {state, process_manager} = case process_manager_module.interested?(event) do
      {:start, process_uuid} ->
        process_manager = start_process_manager(supervisor, process_manager_module, process_uuid)
        state = %Router{state |
          process_managers: Map.put(process_managers, process_uuid, process_manager)
        }
        {state, process_manager}
      {:continue, process_uuid} -> {state, Map.get(process_managers, process_uuid)}
      false -> {state, nil}
    end

    process_event(process_manager, event)

    state
  end

  defp start_process_manager(supervisor, process_manager_module, process_uuid) do
    {:ok, process_manager} = Supervisor.start_process_manager(supervisor, process_manager_module, process_uuid)
    Process.monitor(process_manager)
    process_manager
  end

  defp remove_process_manager(process_managers, pid) do
    Enum.reduce(process_managers, process_managers, fn
      ({process_uuid, process_manager_pid}, acc) when process_manager_pid == pid -> Map.delete(acc, process_uuid)
      (_, acc) -> acc
    end)
  end

  defp process_event(nil, _event), do: nil

  defp process_event(process_manager, event) do
    ProcessManager.process_event(process_manager, event)
  end
end
