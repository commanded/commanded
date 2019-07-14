defmodule Commanded.ProcessManagers.ProcessRouter do
  @moduledoc false

  use GenServer
  use Commanded.Registration

  require Logger

  alias Commanded.Event.Upcast
  alias Commanded.EventStore
  alias Commanded.EventStore.RecordedEvent
  alias Commanded.ProcessManagers.FailureContext
  alias Commanded.ProcessManagers.ProcessManagerInstance
  alias Commanded.ProcessManagers.ProcessRouter
  alias Commanded.ProcessManagers.Supervisor
  alias Commanded.Subscriptions

  defmodule State do
    @moduledoc false

    defstruct [
      :application,
      :consistency,
      :event_timeout,
      :idle_timeout,
      :process_manager_name,
      :process_manager_module,
      :subscribe_from,
      :supervisor,
      :subscription,
      :subscription_ref,
      :last_seen_event,
      :process_event_timer,
      process_managers: %{},
      pending_acks: %{},
      pending_events: []
    ]
  end

  def start_link(application, name, module, opts \\ []) do
    name = {application, ProcessRouter, name}

    state = %State{
      application: application,
      process_manager_name: name,
      process_manager_module: module,
      consistency: Keyword.get(opts, :consistency, :eventual),
      subscribe_from: Keyword.get(opts, :start_from, :origin),
      event_timeout: Keyword.get(opts, :event_timeout),
      idle_timeout: Keyword.get(opts, :idle_timeout, :infinity)
    }

    Registration.start_link(name, __MODULE__, state)
  end

  @impl GenServer
  def init(%State{} = state) do
    :ok = register_subscription(state)

    {:ok, state, {:continue, :subscribe_to_events}}
  end

  @doc """
  Acknowledge successful handling of the given event by a process manager instance
  """
  def ack_event(process_router, %RecordedEvent{} = event, instance) do
    GenServer.cast(process_router, {:ack_event, event, instance})
  end

  @doc false
  def process_instance(process_router, process_uuid) do
    GenServer.call(process_router, {:process_instance, process_uuid})
  end

  @doc false
  def process_instances(process_router) do
    GenServer.call(process_router, :process_instances)
  end

  @doc false
  @impl GenServer
  def handle_continue(:subscribe_to_events, %State{} = state) do
    {:noreply, subscribe_to_events(state)}
  end

  @doc false
  @impl GenServer
  def handle_call(:process_instances, _from, %State{} = state) do
    %State{process_managers: process_managers} = state

    reply = Enum.map(process_managers, fn {process_uuid, pid} -> {process_uuid, pid} end)

    {:reply, reply, state}
  end

  @doc false
  @impl GenServer
  def handle_call({:process_instance, process_uuid}, _from, %State{} = state) do
    %State{process_managers: process_managers} = state

    reply =
      case Map.get(process_managers, process_uuid) do
        nil -> {:error, :process_manager_not_found}
        process_manager -> process_manager
      end

    {:reply, reply, state}
  end

  @doc false
  @impl GenServer
  def handle_cast({:ack_event, event, instance}, %State{} = state) do
    %State{pending_acks: pending_acks} = state
    %RecordedEvent{event_number: event_number} = event

    state =
      case pending_acks |> Map.get(event_number, []) |> List.delete(instance) do
        [] ->
          # Enqueue a message to continue processing any pending events
          GenServer.cast(self(), :process_pending_events)

          state = %State{state | pending_acks: Map.delete(pending_acks, event_number)}

          # no pending acks so confirm receipt of event
          confirm_receipt(event, state)

        pending ->
          # pending acks, don't ack event but wait for outstanding instances
          %State{state | pending_acks: Map.put(pending_acks, event_number, pending)}
      end

    {:noreply, state}
  end

  @doc false
  @impl GenServer
  def handle_cast(:process_pending_events, %State{pending_events: []} = state),
    do: {:noreply, state}

  @doc false
  @impl GenServer
  def handle_cast(:process_pending_events, %State{} = state) do
    %State{pending_events: [event | pending_events]} = state

    case length(pending_events) do
      0 ->
        :ok

      1 ->
        Logger.debug(fn -> describe(state) <> " has 1 pending event to process" end)

      count ->
        Logger.debug(fn -> describe(state) <> " has #{count} pending events to process" end)
    end

    case handle_event(event, state) do
      %State{} = state -> {:noreply, %State{state | pending_events: pending_events}}
      reply -> reply
    end
  end

  @doc false
  # Subscription to event store has successfully subscribed, init process router
  @impl GenServer
  def handle_info({:subscribed, subscription}, %State{subscription: subscription} = state) do
    Logger.debug(fn -> describe(state) <> " has successfully subscribed to event store" end)

    {:ok, supervisor} = Supervisor.start_link()

    {:noreply, %State{state | supervisor: supervisor}}
  end

  @doc false
  @impl GenServer
  def handle_info({:events, events}, %State{} = state) do
    Logger.debug(fn -> describe(state) <> " received #{length(events)} event(s)" end)

    %State{pending_events: pending_events} = state

    unseen_events =
      events
      |> Enum.reject(&event_already_seen?(&1, state))
      |> Upcast.upcast_event_stream()

    state =
      case {pending_events, unseen_events} do
        {[], []} ->
          # no pending or unseen events, so state is unmodified
          state

        {[], _} ->
          # no pending events, but some unseen events so start processing them
          GenServer.cast(self(), :process_pending_events)

          %State{state | pending_events: unseen_events}

        {_, _} ->
          # already processing pending events, append the unseen events so they are processed afterwards
          %State{state | pending_events: pending_events ++ unseen_events}
      end

    {:noreply, state}
  end

  @doc false
  # Shutdown process manager when processing an event has taken too long.
  @impl GenServer
  def handle_info({:event_timeout, event_number}, %State{} = state) do
    %State{pending_acks: pending_acks, event_timeout: event_timeout} = state

    case Map.get(pending_acks, event_number, []) do
      [] ->
        {:noreply, state}

      _pending ->
        Logger.error(fn ->
          describe(state) <>
            " has taken longer than " <>
            inspect(event_timeout) <>
            "ms to process event #" <> inspect(event_number) <> " and is now stopping"
        end)

        {:stop, :event_timeout, state}
    end
  end

  @doc false
  # Stop process manager when event store subscription process terminates.
  @impl GenServer
  def handle_info(
        {:DOWN, ref, :process, pid, reason},
        %State{subscription_ref: ref, subscription: pid} = state
      ) do
    Logger.debug(fn -> describe(state) <> " subscription DOWN due to: #{inspect(reason)}" end)

    {:stop, reason, state}
  end

  @doc false
  # Remove a process manager instance that has stopped with a normal exit reason.
  @impl GenServer
  def handle_info({:DOWN, _ref, :process, pid, :normal}, %State{} = state) do
    %State{process_managers: process_managers} = state

    state = %State{state | process_managers: remove_process_manager(process_managers, pid)}

    {:noreply, state}
  end

  @doc false
  # Stop process router when a process manager instance terminates abnormally.
  @impl GenServer
  def handle_info({:DOWN, _ref, :process, _pid, reason}, %State{} = state) do
    Logger.warn(fn -> describe(state) <> " is stopping due to: #{inspect(reason)}" end)

    {:stop, reason, state}
  end

  # Register this process manager as a subscription with the given consistency
  defp register_subscription(%State{} = state) do
    %State{consistency: consistency, process_manager_name: name} = state

    Subscriptions.register(name, consistency)
  end

  defp subscribe_to_events(%State{} = state) do
    %State{process_manager_name: process_manager_name, subscribe_from: subscribe_from} = state

    {:ok, subscription} =
      EventStore.subscribe_to(:all, process_manager_name, self(), subscribe_from)

    subscription_ref = Process.monitor(subscription)

    %State{state | subscription: subscription, subscription_ref: subscription_ref}
  end

  # Ignore already seen event
  defp event_already_seen?(
         %RecordedEvent{event_number: event_number},
         %State{last_seen_event: last_seen_event}
       ) do
    not is_nil(last_seen_event) and event_number <= last_seen_event
  end

  defp handle_event(%RecordedEvent{} = event, %State{} = state) do
    %RecordedEvent{data: data} = event
    %State{process_manager_module: process_manager_module} = state

    try do
      case process_manager_module.interested?(data) do
        {:start, process_uuid} ->
          Logger.debug(fn -> describe(state) <> " is interested in event " <> describe(event) end)

          process_uuid
          |> List.wrap()
          |> Enum.reduce(state, fn process_uuid, state ->
            {process_instance, state} = start_or_continue_process_manager(process_uuid, state)

            delegate_event(process_instance, event, state)
          end)

        {:start!, process_uuid} ->
          Logger.debug(fn -> describe(state) <> " is interested in event " <> describe(event) end)

          {state, process_instances} =
            process_uuid
            |> List.wrap()
            |> Enum.reduce({state, []}, fn process_uuid, {state, process_instances} ->
              {process_instance, state} = start_or_continue_process_manager(process_uuid, state)

              if ProcessManagerInstance.new?(process_instance) do
                {state, [process_instance | process_instances]}
              else
                throw(
                  handle_routing_error(
                    {:error, {:start!, :process_already_started}},
                    event,
                    state
                  )
                )
              end
            end)

          process_instances
          |> Enum.reverse()
          |> Enum.reduce(state, &delegate_event(&1, event, &2))

        {:continue, process_uuid} ->
          Logger.debug(fn -> describe(state) <> " is interested in event " <> describe(event) end)

          process_uuid
          |> List.wrap()
          |> Enum.reduce(state, fn process_uuid, state ->
            {process_instance, state} = start_or_continue_process_manager(process_uuid, state)

            delegate_event(process_instance, event, state)
          end)

        {:continue!, process_uuid} ->
          Logger.debug(fn -> describe(state) <> " is interested in event " <> describe(event) end)

          {state, process_instances} =
            process_uuid
            |> List.wrap()
            |> Enum.reduce({state, []}, fn process_uuid, {state, process_instances} ->
              {process_instance, state} = start_or_continue_process_manager(process_uuid, state)

              if ProcessManagerInstance.new?(process_instance) do
                throw(
                  handle_routing_error(
                    {:error, {:continue!, :process_not_started}},
                    event,
                    state
                  )
                )
              else
                {state, [process_instance | process_instances]}
              end
            end)

          process_instances
          |> Enum.reverse()
          |> Enum.reduce(state, &delegate_event(&1, event, &2))

        {:stop, process_uuid} ->
          Logger.debug(fn ->
            describe(state) <> " has been stopped by event " <> describe(event)
          end)

          state =
            process_uuid
            |> List.wrap()
            |> Enum.reduce(state, &stop_process_manager/2)

          ack_and_continue(event, state)

        false ->
          Logger.debug(fn ->
            describe(state) <> " is not interested in event " <> describe(event)
          end)

          ack_and_continue(event, state)
      end
    rescue
      e -> handle_routing_error({:error, e}, event, state)
    catch
      reply -> reply
    end
  end

  defp handle_routing_error(error, %RecordedEvent{} = failed_event, %State{} = state) do
    %RecordedEvent{data: data} = failed_event
    %State{process_manager_module: process_manager_module} = state

    failure_context = %FailureContext{last_event: failed_event}

    case process_manager_module.error(error, data, failure_context) do
      :skip ->
        # Skip the problematic event by confirming receipt
        Logger.info(fn -> describe(state) <> " is skipping event" end)

        ack_and_continue(failed_event, state)

      {:stop, reason} ->
        Logger.warn(fn -> describe(state) <> " has requested to stop: #{inspect(error)}" end)

        {:stop, reason, state}

      invalid ->
        Logger.warn(fn ->
          describe(state) <> " returned an invalid error response: #{inspect(invalid)}"
        end)

        {:stop, error, state}
    end
  end

  # Continue processing any pending events and confirm receipt of the given event id
  defp ack_and_continue(%RecordedEvent{} = event, %State{} = state) do
    GenServer.cast(self(), :process_pending_events)

    confirm_receipt(event, state)
  end

  # Confirm receipt of given event
  defp confirm_receipt(%RecordedEvent{event_number: event_number} = event, %State{} = state) do
    Logger.debug(fn ->
      describe(state) <> " confirming receipt of event: #{inspect(event_number)}"
    end)

    do_ack_event(event, state)

    %State{state | last_seen_event: event_number}
  end

  defp start_or_continue_process_manager(process_uuid, %State{} = state) do
    %State{process_managers: process_managers} = state

    case Map.get(process_managers, process_uuid) do
      process_manager when is_pid(process_manager) ->
        {process_manager, state}

      nil ->
        start_process_manager(process_uuid, state)
    end
  end

  defp start_process_manager(process_uuid, %State{} = state) do
    %State{
      application: application,
      idle_timeout: idle_timeout,
      process_managers: process_managers,
      process_manager_name: process_manager_name,
      process_manager_module: process_manager_module,
      supervisor: supervisor
    } = state

    opts = [
      application: application,
      idle_timeout: idle_timeout,
      process_manager_name: process_manager_name,
      process_manager_module: process_manager_module,
      process_router: self(),
      process_uuid: process_uuid
    ]

    {:ok, process_manager} = Supervisor.start_process_manager(supervisor, opts)

    _ref = Process.monitor(process_manager)

    state = %State{
      state
      | process_managers: Map.put(process_managers, process_uuid, process_manager)
    }

    {process_manager, state}
  end

  defp stop_process_manager(process_uuid, %State{} = state) do
    %State{process_managers: process_managers} = state

    case Map.get(process_managers, process_uuid) do
      nil ->
        state

      process_manager ->
        :ok = ProcessManagerInstance.stop(process_manager)

        %State{state | process_managers: Map.delete(process_managers, process_uuid)}
    end
  end

  defp remove_process_manager(process_managers, pid) do
    Enum.reduce(process_managers, process_managers, fn
      {process_uuid, process_manager_pid}, acc when process_manager_pid == pid ->
        Map.delete(acc, process_uuid)

      _, acc ->
        acc
    end)
  end

  defp do_ack_event(event, %State{} = state) do
    %State{consistency: consistency, process_manager_name: name, subscription: subscription} =
      state

    :ok = EventStore.ack_event(subscription, event)
    :ok = Subscriptions.ack_event(name, consistency, event)
  end

  # Delegate event to process instance who will ack event processing on success
  defp delegate_event(process_instance, %RecordedEvent{} = event, %State{} = state) do
    %State{pending_acks: pending_acks} = state
    %RecordedEvent{event_number: event_number} = event

    :ok = ProcessManagerInstance.process_event(process_instance, event)

    pending_acks =
      Map.update(pending_acks, event_number, [process_instance], fn
        pending -> [process_instance | pending]
      end)

    state = %State{state | pending_acks: pending_acks}

    start_event_timer(event_number, state)
  end

  # Event timeout not configured
  defp start_event_timer(_event_number, %State{event_timeout: nil} = state), do: state

  defp start_event_timer(event_number, %State{process_event_timer: process_event_timer} = state)
       when is_reference(process_event_timer) do
    Process.cancel_timer(process_event_timer)

    state = %State{state | process_event_timer: nil}

    start_event_timer(event_number, state)
  end

  defp start_event_timer(event_number, %State{event_timeout: event_timeout} = state)
       when is_integer(event_timeout) do
    %State{event_timeout: event_timeout} = state

    process_event_timer =
      Process.send_after(self(), {:event_timeout, event_number}, event_timeout)

    %State{state | process_event_timer: process_event_timer}
  end

  defp describe(%State{process_manager_module: process_manager_module}),
    do: inspect(process_manager_module)

  defp describe(%RecordedEvent{} = event) do
    %RecordedEvent{
      event_number: event_number,
      stream_id: stream_id,
      stream_version: stream_version
    } = event

    "#{inspect(event_number)} (#{inspect(stream_id)}@#{inspect(stream_version)})"
  end
end
