defmodule Commanded.ProcessManagers.ProcessRouter do
  @moduledoc false
  use GenServer

  require Logger

  alias Commanded.ProcessManagers.{
    ProcessManagerInstance,
    Supervisor,
  }
  alias Commanded.EventStore
  alias Commanded.EventStore.RecordedEvent
  alias Commanded.Subscriptions

  defmodule State do
    defstruct [
      command_dispatcher: nil,
      consistency: nil,
      process_manager_name: nil,
      process_manager_module: nil,
      subscribe_from: nil,
      process_managers: %{},
      supervisor: nil,
      last_seen_event: nil,
      pending_events: [],
      subscription: nil,
    ]
  end

  def start_link(process_manager_name, process_manager_module, command_dispatcher, opts \\ []) do
    GenServer.start_link(__MODULE__, %State{
      process_manager_name: process_manager_name,
      process_manager_module: process_manager_module,
      command_dispatcher: command_dispatcher,
      consistency: opts[:consistency] || :eventual,
      subscribe_from: opts[:start_from] || :origin,
    }, [name: process_manager_module])
  end

  def init(%State{command_dispatcher: command_dispatcher} = state) do
    {:ok, supervisor} = Supervisor.start_link(command_dispatcher)

    state = %State{state | supervisor: supervisor}

    GenServer.cast(self(), {:subscribe_to_events})

    {:ok, state}
  end

  @doc """
  Acknowledge successful handling of the given event by a process manager instance
  """
  def ack_event(process_router, %RecordedEvent{} = event) do
    GenServer.cast(process_router, {:ack_event, event})
  end

  @doc """
  Fetch the pid of an individual process manager instance identified by the given `process_uuid`
  """
  def process_instance(process_router, process_uuid) do
    GenServer.call(process_router, {:process_instance, process_uuid})
  end

  def handle_call({:process_instance, process_uuid}, _from, %State{process_managers: process_managers} = state) do
    reply = case Map.get(process_managers, process_uuid) do
      nil -> {:error, :process_manager_not_found}
      process_manager -> process_manager
    end

    {:reply, reply, state}
  end

  def handle_cast({:ack_event, event}, %State{} = state) do
    state = confirm_receipt(event, state)

    # continue processing any pending events
    GenServer.cast(self(), {:process_pending_events})

    {:noreply, state}
  end

  @doc """
  Subscribe the process router to all events
  """
  def handle_cast({:subscribe_to_events}, %State{} = state) do
    {:noreply, subscribe_to_all_streams(state)}
  end

  def handle_cast({:process_pending_events}, %State{pending_events: []} = state), do: {:noreply, state}
  def handle_cast({:process_pending_events}, %State{pending_events: [event | pending_events], process_manager_name: process_manager_name} = state) do
    Logger.debug(fn ->  "process router \"#{process_manager_name}\" has #{length(pending_events)} pending event(s) to process" end)

    state = handle_event(event, state)

    {:noreply, %State{state | pending_events: pending_events}}
  end

  def handle_info({:events, events}, %State{process_manager_name: process_manager_name, pending_events: pending_events} = state) do
    Logger.debug(fn -> "process router \"#{process_manager_name}\" received #{length(events)} event(s)" end)

    unseen_events = Enum.reject(events, &event_already_seen?(&1, state))

    state = case {pending_events, unseen_events} do
      {[], []} ->
        # no pending or unseen events, so state is unmodified
        state

      {[], _} ->
        # no pending events, but some unseen events so start processing them
        GenServer.cast(self(), {:process_pending_events})
        %State{state | pending_events: unseen_events}

      {_, _} ->
        # already processing pending events, append the unseen events so they are processed afterwards
        %State{state | pending_events: pending_events ++ unseen_events}
    end

    {:noreply, state}
  end

  def handle_info({:DOWN, _ref, :process, pid, reason}, %State{process_managers: process_managers} = state) do
    Logger.warn(fn -> "process manager process down due to: #{inspect reason}" end)

    {:noreply, %State{state | process_managers: remove_process_manager(process_managers, pid)}}
  end

  defp subscribe_to_all_streams(%State{consistency: consistency, process_manager_name: process_manager_name, subscribe_from: subscribe_from} = state) do
    {:ok, subscription} = EventStore.subscribe_to_all_streams(process_manager_name, self(), subscribe_from)

    # register this event handler as a subscription with the given consistency
    :ok = Subscriptions.register(process_manager_name, consistency)

    %State{state | subscription: subscription}
  end

  # ignore already seen event
  defp event_already_seen?(%RecordedEvent{event_number: event_number}, %State{last_seen_event: last_seen_event}) do
    not is_nil(last_seen_event) and event_number <= last_seen_event
  end

  defp handle_event(%RecordedEvent{event_number: event_number, data: data, stream_id: stream_id, stream_version: stream_version} = event, %State{process_manager_name: process_manager_name, process_manager_module: process_manager_module, process_managers: process_managers} = state) do
    {process_uuid, process_manager} = case process_manager_module.interested?(data) do
      {:start, process_uuid} -> {process_uuid, start_process_manager(process_uuid, state)}
      {:continue, process_uuid} -> {process_uuid, continue_process_manager(process_uuid, state)}
      {:stop, process_uuid} -> {:stopped, stop_process_manager(process_uuid, state)}
      false -> {nil, nil}
    end

    case process_uuid do
      nil ->
        Logger.debug(fn -> "process router \"#{process_manager_name}\" is not interested in event: #{inspect event_number} (#{inspect stream_id}@#{inspect stream_version})" end)

        ack_and_continue(event, state)

      :stopped ->
        Logger.debug(fn -> "process manager instance \"#{process_manager_name}\" has been stopped by event: #{inspect event_number} (#{inspect stream_id}@#{inspect stream_version})" end)

        ack_and_continue(event, state)

      _ ->
        Logger.debug(fn -> "process router \"#{process_manager_name}\" is interested in event: #{inspect event_number} (#{inspect stream_id}@#{inspect stream_version})" end)

        # delegate event to process instance who will ack event processing on success
        :ok = delegate_event(process_manager, event)

        %State{state | process_managers: Map.put(process_managers, process_uuid, process_manager)}
    end
  end

  # continue processing any pending events and confirm receipt of the given event id
  defp ack_and_continue(%RecordedEvent{} = event, %State{} = state) do
    GenServer.cast(self(), {:process_pending_events})

    confirm_receipt(event, state)
  end

  # confirm receipt of given event
  defp confirm_receipt(%RecordedEvent{event_number: event_number} = event, %State{process_manager_name: process_manager_name} = state) do
    Logger.debug(fn -> "process router \"#{process_manager_name}\" confirming receipt of event: #{inspect event_number}" end)

    do_ack_event(event, state)

    %State{state | last_seen_event: event_number}
  end

  defp start_process_manager(process_uuid, %State{process_manager_name: process_manager_name, process_manager_module: process_manager_module, supervisor: supervisor}) do
    {:ok, process_manager} = Supervisor.start_process_manager(supervisor, process_manager_name, process_manager_module, process_uuid)
    Process.monitor(process_manager)
    process_manager
  end

  defp continue_process_manager(process_uuid, %State{process_managers: process_managers} = state) do
    case Map.get(process_managers, process_uuid) do
      nil -> start_process_manager(process_uuid, state)
      process_manager -> process_manager
    end
  end

  defp stop_process_manager(process_uuid, %State{process_managers: process_managers}) do
    case Map.get(process_managers, process_uuid) do
      nil -> nil
      process_manager ->
        :ok = ProcessManagerInstance.stop(process_manager)
        nil
    end
  end

  defp remove_process_manager(process_managers, pid) do
    Enum.reduce(process_managers, process_managers, fn
      ({process_uuid, process_manager_pid}, acc) when process_manager_pid == pid -> Map.delete(acc, process_uuid)
      (_, acc) -> acc
    end)
  end

  defp do_ack_event(event, %State{consistency: consistency, process_manager_name: name, subscription: subscription}) do
    EventStore.ack_event(subscription, event)
    Subscriptions.ack_event(name, consistency, event)
  end

  defp delegate_event(nil, _event), do: :ok
  defp delegate_event(process_manager, %RecordedEvent{} = event) do
    ProcessManagerInstance.process_event(process_manager, event, self())
  end
end
