defmodule Commanded.ProcessManagers.ProcessRouter do
  @moduledoc false

  use GenServer
  use Commanded.Registration

  require Logger

  alias Commanded.Event.Upcast
  alias Commanded.EventStore.RecordedEvent
  alias Commanded.EventStore.Subscription
  alias Commanded.ProcessManagers.FailureContext
  alias Commanded.ProcessManagers.ProcessManagerInstance
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
      :supervisor,
      :subscription,
      :subscribe_timer,
      :last_seen_event,
      :process_event_timer,
      process_managers: %{},
      pending_acks: %{},
      pending_events: []
    ]
  end

  def start_link(application, process_name, process_module, opts \\ []) do
    {start_opts, router_opts} =
      Keyword.split(opts, [:debug, :name, :timeout, :spawn_opt, :hibernate_after])

    name = name(application, process_name)
    consistency = Keyword.get(router_opts, :consistency, :eventual)

    subscription =
      Subscription.new(
        application: application,
        subscription_name: process_name,
        subscribe_from: Keyword.get(router_opts, :start_from, :origin),
        subscribe_to: Keyword.get(router_opts, :subscribe_to, :all),
        subscription_opts: Keyword.get(router_opts, :subscription_opts, [])
      )

    state = %State{
      application: application,
      process_manager_name: process_name,
      process_manager_module: process_module,
      consistency: consistency,
      subscription: subscription,
      event_timeout: Keyword.get(router_opts, :event_timeout),
      idle_timeout: Keyword.get(router_opts, :idle_timeout, :infinity)
    }

    with {:ok, pid} <- Registration.start_link(application, name, __MODULE__, state, start_opts) do
      # Register the process manager as a subscription with the given consistency.
      :ok = Subscriptions.register(application, process_name, process_module, pid, consistency)

      {:ok, pid}
    end
  end

  @doc false
  def name(application, process_name), do: {application, __MODULE__, process_name}

  # Acknowledge successful handling of the given event by a process manager instance.
  def ack_event(process_router, %RecordedEvent{} = event, instance) do
    GenServer.cast(process_router, {:ack_event, event, instance})
  end

  def process_instance(process_router, process_uuid) do
    GenServer.call(process_router, {:process_instance, process_uuid})
  end

  def process_instances(process_router) do
    GenServer.call(process_router, :process_instances)
  end

  @impl GenServer
  def init(%State{} = state) do
    {:ok, state, {:continue, :subscribe_to_events}}
  end

  @impl GenServer
  def handle_continue(:subscribe_to_events, %State{} = state) do
    {:noreply, subscribe_to_events(state)}
  end

  @impl GenServer
  def handle_call(:process_instances, _from, %State{} = state) do
    %State{process_managers: process_managers} = state

    reply = Enum.map(process_managers, fn {process_uuid, pid} -> {process_uuid, pid} end)

    {:reply, reply, state}
  end

  @impl GenServer
  def handle_call({:process_instance, process_uuid}, _from, %State{} = state) do
    reply = get_process_manager(state, process_uuid)

    {:reply, reply, state}
  end

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

  @impl GenServer
  def handle_cast(:process_pending_events, %State{pending_events: []} = state),
    do: {:noreply, state}

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
  @impl GenServer
  def handle_info(:subscribe_to_events, %State{} = state) do
    {:noreply, subscribe_to_events(state)}
  end

  @doc false
  # Subscription to event store has successfully subscribed, init process router
  @impl GenServer
  def handle_info(
        {:subscribed, subscription},
        %State{subscription: %Subscription{subscription_pid: subscription}} = state
      ) do
    Logger.debug(fn -> describe(state) <> " has successfully subscribed to event store" end)

    {:ok, supervisor} = Supervisor.start_link()

    {:noreply, %State{state | supervisor: supervisor}}
  end

  @impl GenServer
  def handle_info({:events, events}, %State{} = state) do
    %State{application: application, pending_events: pending_events} = state

    Logger.debug(fn -> describe(state) <> " received #{length(events)} event(s)" end)

    # Exclude already seen events
    unseen_events =
      events
      |> Enum.reject(&event_already_seen?(&1, state))
      |> Upcast.upcast_event_stream(additional_metadata: %{application: application})

    state =
      case {pending_events, unseen_events} do
        {[], []} ->
          # No pending or unseen events, so state is unmodified
          state

        {[], _} ->
          # No pending events, but some unseen events so start processing them
          GenServer.cast(self(), :process_pending_events)

          %State{state | pending_events: unseen_events}

        {_, _} ->
          # Already processing pending events, append the unseen events so they are processed afterwards
          %State{state | pending_events: pending_events ++ unseen_events}
      end

    {:noreply, state}
  end

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

  # Stop process manager when event store subscription process terminates.
  @impl GenServer
  def handle_info(
        {:DOWN, ref, :process, _pid, reason},
        %State{subscription: %Subscription{subscription_ref: ref}} = state
      ) do
    Logger.debug(fn -> describe(state) <> " subscription DOWN due to: #{inspect(reason)}" end)

    {:stop, reason, state}
  end

  # Remove a process manager instance that has stopped with a normal exit reason.
  @impl GenServer
  def handle_info({:DOWN, _ref, :process, pid, :normal}, %State{} = state) do
    %State{process_managers: process_managers} = state

    state = %State{state | process_managers: remove_process_manager(process_managers, pid)}

    {:noreply, state}
  end

  # Stop process router when a process manager instance terminates abnormally.
  @impl GenServer
  def handle_info({:DOWN, _ref, :process, _pid, reason}, %State{} = state) do
    Logger.warn(fn -> describe(state) <> " is stopping due to: #{inspect(reason)}" end)

    {:stop, reason, state}
  end

  defp subscribe_to_events(%State{} = state) do
    %State{subscription: subscription} = state

    case Subscription.subscribe(subscription, self()) do
      {:ok, subscription} ->
        %State{state | subscription: subscription, subscribe_timer: nil}

      {:error, error} ->
        {backoff, subscription} = Subscription.backoff(subscription)

        Logger.info(fn ->
          describe(state) <>
            " failed to subscribe to event store due to: " <>
            inspect(error) <> ", retrying in " <> inspect(backoff) <> "ms"
        end)

        subscribe_timer = Process.send_after(self(), :subscribe_to_events, backoff)

        %State{state | subscription: subscription, subscribe_timer: subscribe_timer}
    end
  end

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
        {:start, []} ->
          ack_and_continue(event, state)

        {:start, process_uuid} ->
          Logger.debug(fn -> describe(state) <> " is interested in event " <> describe(event) end)

          process_uuid
          |> List.wrap()
          |> Enum.reduce(state, fn process_uuid, state ->
            {process_instance, state} = start_or_continue_process_manager(process_uuid, state)

            delegate_event(process_instance, event, state)
          end)

        {:start!, []} ->
          ack_and_continue(event, state)

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
                error = {:error, {:start!, :process_already_started}}
                reply = handle_routing_error(error, event, state)

                throw(reply)
              end
            end)

          process_instances
          |> Enum.reverse()
          |> Enum.reduce(state, &delegate_event(&1, event, &2))

        {:continue, []} ->
          ack_and_continue(event, state)

        {:continue, process_uuid} ->
          Logger.debug(fn -> describe(state) <> " is interested in event " <> describe(event) end)

          process_uuid
          |> List.wrap()
          |> Enum.reduce(state, fn process_uuid, state ->
            {process_instance, state} = start_or_continue_process_manager(process_uuid, state)

            delegate_event(process_instance, event, state)
          end)

        {:continue!, []} ->
          ack_and_continue(event, state)

        {:continue!, process_uuid} ->
          Logger.debug(fn -> describe(state) <> " is interested in event " <> describe(event) end)

          {state, process_instances} =
            process_uuid
            |> List.wrap()
            |> Enum.reduce({state, []}, fn process_uuid, {state, process_instances} ->
              {process_instance, state} = start_or_continue_process_manager(process_uuid, state)

              if ProcessManagerInstance.new?(process_instance) do
                error = {:error, {:continue!, :process_not_started}}
                reply = handle_routing_error(error, event, state)

                throw(reply)
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
    %State{
      application: application,
      consistency: consistency,
      process_manager_name: name,
      subscription: subscription
    } = state

    Logger.debug(fn ->
      describe(state) <> " confirming receipt of event: #{inspect(event_number)}"
    end)

    :ok = Subscription.ack_event(subscription, event)
    :ok = Subscriptions.ack_event(application, name, consistency, event)

    %State{state | last_seen_event: event_number}
  end

  defp start_or_continue_process_manager(process_uuid, %State{} = state) do
    case get_process_manager(state, process_uuid) do
      {:ok, process_manager} ->
        {process_manager, state}

      {:error, :process_manager_not_found} ->
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

    case get_process_manager(state, process_uuid) do
      {:ok, process_manager} ->
        :ok = ProcessManagerInstance.stop(process_manager)

        %State{state | process_managers: Map.delete(process_managers, process_uuid)}

      {:error, :process_manager_not_found} ->
        state
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

  defp get_process_manager(%State{} = state, process_uuid) do
    %State{process_managers: process_managers} = state

    case Map.get(process_managers, process_uuid) do
      process_manager when is_pid(process_manager) -> {:ok, process_manager}
      nil -> {:error, :process_manager_not_found}
    end
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
