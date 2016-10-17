defmodule Commanded.ProcessManagers.ProcessRouter do
  @moduledoc """
  Process router is responsible for starting, continuing and completing process managers in response to raised domain events.
  """

  use GenServer
  require Logger

  alias Commanded.ProcessManagers.{ProcessManagerInstance,Supervisor}
  alias Commanded.Event.Mapper

  defmodule State do
    defstruct process_manager_name: nil, process_manager_module: nil, command_dispatcher: nil, process_managers: %{}, supervisor: nil, last_seen_event_id: nil
  end

  def start_link(process_manager_name, process_manager_module, command_dispatcher) do
    GenServer.start_link(__MODULE__, %State{
      process_manager_name: process_manager_name,
      process_manager_module: process_manager_module,
      command_dispatcher: command_dispatcher
    })
  end

  def init(%State{command_dispatcher: command_dispatcher} = state) do
    {:ok, supervisor} = Supervisor.start_link(command_dispatcher)

    state = %State{state | supervisor: supervisor}

    GenServer.cast(self, {:subscribe_to_events})

    {:ok, state}
  end

  @doc """
  Fetch the state of an individual process manager instance identified by the given `process_uuid`
  """
  def process_state(process_router, process_uuid) do
    GenServer.call(process_router, {:process_state, process_uuid})
  end

  def handle_call({:process_state, process_uuid}, _from, %State{process_managers: process_managers} = state) do
    reply = case Map.get(process_managers, process_uuid) do
      nil -> {:error, :process_manager_not_found}
      process_manager -> ProcessManagerInstance.process_state(process_manager)
    end

    {:reply, reply, state}
  end

  def handle_cast({:subscribe_to_events}, %State{process_manager_name: process_manager_name} = state) do
    {:ok, _} = EventStore.subscribe_to_all_streams(process_manager_name, self)
    {:noreply, state}
  end

  def handle_info({:events, events, subscription}, %State{process_manager_name: process_manager_name} = state) do
    Logger.debug(fn -> "process manager router \"#{process_manager_name}\" received events: #{inspect events}" end)

    state =
      events
      |> Enum.filter(fn event -> !already_seen_event?(event, state) end)
      |> Enum.map(&Mapper.map_from_recorded_event/1)
      |> Enum.reduce(state, fn (event, state) -> handle_event(event, state) end)

    state = confirm_receipt(state, subscription, events)

    {:noreply, state}
  end

  def handle_info({:DOWN, _ref, :process, pid, reason}, %State{process_managers: process_managers} = state) do
    Logger.warn(fn -> "process manager process down due to: #{inspect reason}" end)

    {:noreply, %State{state | process_managers: remove_process_manager(process_managers, pid)}}
  end

  # ignore already seen event
  defp already_seen_event?(%EventStore.RecordedEvent{event_id: event_id} = event, %State{last_seen_event_id: last_seen_event_id}) when not is_nil(last_seen_event_id) and event_id <= last_seen_event_id do
    Logger.debug(fn -> "process manager has already seen event: #{inspect event}" end)
    true
  end
  defp already_seen_event?(_event, _state), do: false

  defp handle_event(event, %State{process_manager_module: process_manager_module, process_managers: process_managers, supervisor: supervisor} = state) do
    {process_uuid, process_manager} = case process_manager_module.interested?(event) do
      {:start, process_uuid} -> {process_uuid, start_process_manager(supervisor, process_manager_module, process_uuid)}
      {:continue, process_uuid} -> {process_uuid, continue_process_manager(process_managers, supervisor, process_manager_module, process_uuid)}
      false -> {nil, nil}
    end

    state = case process_uuid do
      nil -> state
      _ -> %State{state | process_managers: Map.put(process_managers, process_uuid, process_manager)}
    end

    process_event(process_manager, event)

    state
  end

  # confirm receipt of events
  defp confirm_receipt(%State{} = state, subscription, events) do
    last_seen_event_id = List.last(events).event_id

    Logger.debug(fn -> "process router confirming receipt of event: #{last_seen_event_id}" end)

    send(subscription, {:ack, last_seen_event_id})

    %State{state | last_seen_event_id: last_seen_event_id}
  end

  defp start_process_manager(supervisor, process_manager_module, process_uuid) do
    {:ok, process_manager} = Supervisor.start_process_manager(supervisor, process_manager_module, process_uuid)
    Process.monitor(process_manager)
    process_manager
  end

  defp continue_process_manager(process_managers, supervisor, process_manager_module, process_uuid) do
    case Map.get(process_managers, process_uuid) do
      nil -> start_process_manager(supervisor, process_manager_module, process_uuid)
      process_manager -> process_manager
    end
  end

  defp remove_process_manager(process_managers, pid) do
    Enum.reduce(process_managers, process_managers, fn
      ({process_uuid, process_manager_pid}, acc) when process_manager_pid == pid -> Map.delete(acc, process_uuid)
      (_, acc) -> acc
    end)
  end

  defp process_event(nil, _event), do: nil

  defp process_event(process_manager, event) do
    ProcessManagerInstance.process_event(process_manager, event)
  end
end
