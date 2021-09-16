defmodule Commanded.EventStore.Adapters.InMemory do
  @moduledoc """
  An in-memory event store adapter useful for testing as no persistence provided.
  """

  @behaviour Commanded.EventStore.Adapter

  use GenServer

  defmodule State do
    @moduledoc false

    defstruct [
      :name,
      :serializer,
      persisted_events: [],
      streams: %{},
      transient_subscribers: %{},
      persistent_subscriptions: %{},
      snapshots: %{},
      next_event_number: 1
    ]
  end

  alias Commanded.EventStore.Adapters.InMemory.{State, Subscription}
  alias Commanded.EventStore.{EventData, RecordedEvent, SnapshotData}

  def start_link(opts \\ []) do
    {start_opts, in_memory_opts} =
      Keyword.split(opts, [:debug, :name, :timeout, :spawn_opt, :hibernate_after])

    state = %State{
      name: Keyword.fetch!(opts, :name),
      serializer: Keyword.get(in_memory_opts, :serializer)
    }

    GenServer.start_link(__MODULE__, state, start_opts)
  end

  @impl GenServer
  def init(%State{} = state) do
    {:ok, state}
  end

  @impl Commanded.EventStore.Adapter
  def child_spec(application, config) do
    {event_store_name, config} = parse_config(application, config)

    supervisor_name = subscriptions_name(event_store_name)

    child_spec = [
      {DynamicSupervisor, strategy: :one_for_one, name: supervisor_name},
      %{
        id: event_store_name,
        start: {__MODULE__, :start_link, [config]}
      }
    ]

    {:ok, child_spec, %{name: event_store_name}}
  end

  @impl Commanded.EventStore.Adapter
  def append_to_stream(adapter_meta, stream_uuid, expected_version, events) do
    event_store = event_store_name(adapter_meta)

    GenServer.call(event_store, {:append, stream_uuid, expected_version, events})
  end

  @impl Commanded.EventStore.Adapter
  def stream_forward(
        adapter_meta,
        stream_uuid,
        start_version \\ 0,
        _read_batch_size \\ 1_000
      ) do
    event_store = event_store_name(adapter_meta)

    GenServer.call(event_store, {:stream_forward, stream_uuid, start_version})
  end

  @impl Commanded.EventStore.Adapter
  def subscribe(adapter_meta, stream_uuid) do
    event_store = event_store_name(adapter_meta)

    GenServer.call(event_store, {:subscribe, stream_uuid, self()})
  end

  @impl Commanded.EventStore.Adapter
  def subscribe_to(adapter_meta, stream_uuid, subscription_name, subscriber, start_from, _options) do
    event_store = event_store_name(adapter_meta)

    subscription = %Subscription{
      stream_uuid: stream_uuid,
      name: subscription_name,
      subscriber: subscriber,
      start_from: start_from
    }

    GenServer.call(event_store, {:subscribe_to, subscription})
  end

  @impl Commanded.EventStore.Adapter
  def ack_event(adapter_meta, subscription, %RecordedEvent{} = event) when is_pid(subscription) do
    event_store = event_store_name(adapter_meta)

    GenServer.call(event_store, {:ack_event, event, subscription})
  end

  @impl Commanded.EventStore.Adapter
  def unsubscribe(adapter_meta, subscription) when is_pid(subscription) do
    event_store = event_store_name(adapter_meta)

    GenServer.call(event_store, {:unsubscribe, subscription})
  end

  @impl Commanded.EventStore.Adapter
  def delete_subscription(adapter_meta, stream_uuid, subscription_name) do
    event_store = event_store_name(adapter_meta)

    GenServer.call(event_store, {:delete_subscription, stream_uuid, subscription_name})
  end

  @impl Commanded.EventStore.Adapter
  def read_snapshot(adapter_meta, source_uuid) do
    event_store = event_store_name(adapter_meta)

    GenServer.call(event_store, {:read_snapshot, source_uuid})
  end

  @impl Commanded.EventStore.Adapter
  def record_snapshot(adapter_meta, snapshot) do
    event_store = event_store_name(adapter_meta)

    GenServer.call(event_store, {:record_snapshot, snapshot})
  end

  @impl Commanded.EventStore.Adapter
  def delete_snapshot(adapter_meta, source_uuid) do
    event_store = event_store_name(adapter_meta)

    GenServer.call(event_store, {:delete_snapshot, source_uuid})
  end

  def reset!(application, config \\ []) do
    {event_store, _config} = parse_config(application, config)

    GenServer.call(event_store, :reset!)
  end

  @impl GenServer
  def handle_call({:append, stream_uuid, :stream_exists, events}, _from, %State{} = state) do
    %State{streams: streams} = state

    {reply, state} =
      case Map.get(streams, stream_uuid) do
        nil ->
          {{:error, :stream_does_not_exist}, state}

        existing_events ->
          persist_events(stream_uuid, existing_events, events, state)
      end

    {:reply, reply, state}
  end

  @impl GenServer
  def handle_call({:append, stream_uuid, :no_stream, events}, _from, %State{} = state) do
    %State{streams: streams} = state

    {reply, state} =
      case Map.get(streams, stream_uuid) do
        nil ->
          persist_events(stream_uuid, [], events, state)

        _existing_events ->
          {{:error, :stream_exists}, state}
      end

    {:reply, reply, state}
  end

  @impl GenServer
  def handle_call({:append, stream_uuid, :any_version, events}, _from, %State{} = state) do
    %State{streams: streams} = state

    existing_events = Map.get(streams, stream_uuid, [])

    {:ok, state} = persist_events(stream_uuid, existing_events, events, state)

    {:reply, :ok, state}
  end

  @impl GenServer
  def handle_call({:append, stream_uuid, expected_version, events}, _from, %State{} = state)
      when is_integer(expected_version) do
    %State{streams: streams} = state

    {reply, state} =
      case Map.get(streams, stream_uuid) do
        nil ->
          case expected_version do
            0 ->
              persist_events(stream_uuid, [], events, state)

            _ ->
              {{:error, :wrong_expected_version}, state}
          end

        existing_events
        when length(existing_events) != expected_version ->
          {{:error, :wrong_expected_version}, state}

        existing_events ->
          persist_events(stream_uuid, existing_events, events, state)
      end

    {:reply, reply, state}
  end

  @impl GenServer
  def handle_call({:stream_forward, stream_uuid, start_version}, _from, %State{} = state) do
    %State{streams: streams} = state

    reply =
      case Map.get(streams, stream_uuid) do
        nil ->
          {:error, :stream_not_found}

        events ->
          events
          |> Enum.reverse()
          |> Stream.drop(max(0, start_version - 1))
          |> Stream.map(&deserialize(&1, state))
          |> set_event_number_from_version()
      end

    {:reply, reply, state}
  end

  @impl GenServer
  def handle_call({:subscribe, stream_uuid, subscriber}, _from, %State{} = state) do
    %State{transient_subscribers: transient_subscribers} = state

    Process.monitor(subscriber)

    transient_subscribers =
      Map.update(transient_subscribers, stream_uuid, [subscriber], fn transient ->
        [subscriber | transient]
      end)

    {:reply, :ok, %State{state | transient_subscribers: transient_subscribers}}
  end

  @impl GenServer
  def handle_call({:subscribe_to, %Subscription{} = subscription}, _from, %State{} = state) do
    %Subscription{name: subscription_name, subscriber: subscriber} = subscription
    %State{persistent_subscriptions: subscriptions} = state

    {reply, state} =
      case Map.get(subscriptions, subscription_name) do
        nil ->
          persistent_subscription(subscription, state)

        %Subscription{subscriber: nil} = subscription ->
          subscription = %Subscription{subscription | subscriber: subscriber}

          persistent_subscription(subscription, state)

        %Subscription{} ->
          {{:error, :subscription_already_exists}, state}
      end

    {:reply, reply, state}
  end

  @impl GenServer
  def handle_call({:unsubscribe, pid}, _from, %State{} = state) do
    %State{persistent_subscriptions: subscriptions} = state

    {reply, state} =
      case Enum.find(subscriptions, fn
             {_name, %Subscription{subscriber: ^pid}} -> true
             {_name, %Subscription{}} -> false
           end) do
        {subscription_name, %Subscription{} = subscription} ->
          :ok = stop_subscription(pid, state)

          subscription = %Subscription{subscription | subscriber: nil, ref: nil}

          state = %State{
            state
            | persistent_subscriptions: Map.put(subscriptions, subscription_name, subscription)
          }

          {:ok, state}

        nil ->
          {:ok, state}
      end

    {:reply, reply, state}
  end

  @impl GenServer
  def handle_call({:delete_subscription, stream_uuid, subscription_name}, _from, %State{} = state) do
    %State{persistent_subscriptions: subscriptions} = state

    {reply, state} =
      case Map.get(subscriptions, subscription_name) do
        %Subscription{stream_uuid: ^stream_uuid, subscriber: nil} ->
          state = %State{
            state
            | persistent_subscriptions: Map.delete(subscriptions, subscription_name)
          }

          {:ok, state}

        nil ->
          {{:error, :subscription_not_found}, state}
      end

    {:reply, reply, state}
  end

  @impl GenServer
  def handle_call({:read_snapshot, source_uuid}, _from, %State{} = state) do
    %State{snapshots: snapshots} = state

    reply =
      case Map.get(snapshots, source_uuid, nil) do
        nil -> {:error, :snapshot_not_found}
        snapshot -> {:ok, deserialize(snapshot, state)}
      end

    {:reply, reply, state}
  end

  @impl GenServer
  def handle_call({:record_snapshot, %SnapshotData{} = snapshot}, _from, %State{} = state) do
    %SnapshotData{source_uuid: source_uuid} = snapshot
    %State{snapshots: snapshots} = state

    state = %State{state | snapshots: Map.put(snapshots, source_uuid, serialize(snapshot, state))}

    {:reply, :ok, state}
  end

  @impl GenServer
  def handle_call({:delete_snapshot, source_uuid}, _from, %State{} = state) do
    %State{snapshots: snapshots} = state

    state = %State{state | snapshots: Map.delete(snapshots, source_uuid)}

    {:reply, :ok, state}
  end

  def handle_call(:reset!, _from, %State{} = state) do
    %State{
      name: name,
      serializer: serializer,
      persistent_subscriptions: subscriptions
    } = state

    for {_name, %Subscription{subscriber: subscriber}} <- subscriptions, is_pid(subscriber) do
      _ = stop_subscription(subscriber, state)
    end

    initial_state = %State{name: name, serializer: serializer}

    {:reply, :ok, initial_state}
  end

  @impl GenServer
  def handle_call({:ack_event, event, subscriber}, _from, %State{} = state) do
    state = ack_subscription_by_pid(event, subscriber, state)

    {:reply, :ok, state}
  end

  @impl GenServer
  def handle_info({:DOWN, _ref, :process, pid, _reason}, %State{} = state) do
    %State{persistent_subscriptions: persistent, transient_subscribers: transient} = state

    state = %State{
      state
      | persistent_subscriptions: remove_subscriber_by_pid(persistent, pid),
        transient_subscribers: remove_transient_subscriber_by_pid(transient, pid)
    }

    {:noreply, state}
  end

  defp persist_events(stream_uuid, existing_events, new_events, %State{} = state) do
    %State{
      persisted_events: persisted_events,
      streams: streams,
      next_event_number: next_event_number
    } = state

    initial_stream_version = length(existing_events) + 1
    now = DateTime.utc_now()

    new_events =
      new_events
      |> Enum.with_index(0)
      |> Enum.map(fn {recorded_event, index} ->
        event_number = next_event_number + index
        stream_version = initial_stream_version + index

        map_to_recorded_event(event_number, stream_uuid, stream_version, now, recorded_event)
      end)
      |> Enum.map(&serialize(&1, state))

    stream_events = prepend(existing_events, new_events)
    next_event_number = List.last(new_events).event_number + 1

    state = %State{
      state
      | streams: Map.put(streams, stream_uuid, stream_events),
        persisted_events: prepend(persisted_events, new_events),
        next_event_number: next_event_number
    }

    publish_all_events = Enum.map(new_events, &deserialize(&1, state))

    publish_to_transient_subscribers(:all, publish_all_events, state)
    publish_to_persistent_subscriptions(:all, publish_all_events, state)

    publish_stream_events = set_event_number_from_version(publish_all_events)

    publish_to_transient_subscribers(stream_uuid, publish_stream_events, state)
    publish_to_persistent_subscriptions(stream_uuid, publish_stream_events, state)

    {:ok, state}
  end

  # Event number should equal stream version for stream events.
  defp set_event_number_from_version(events) do
    Enum.map(events, fn %RecordedEvent{stream_version: stream_version} = event ->
      %RecordedEvent{event | event_number: stream_version}
    end)
  end

  defp prepend(list, []), do: list
  defp prepend(list, [item | remainder]), do: prepend([item | list], remainder)

  defp map_to_recorded_event(event_number, stream_uuid, stream_version, now, %EventData{} = event) do
    %EventData{
      event_id: event_id,
      causation_id: causation_id,
      correlation_id: correlation_id,
      event_type: event_type,
      data: data,
      metadata: metadata
    } = event

    %RecordedEvent{
      event_id: event_id,
      event_number: event_number,
      stream_id: stream_uuid,
      stream_version: stream_version,
      causation_id: causation_id,
      correlation_id: correlation_id,
      event_type: event_type,
      data: data,
      metadata: metadata,
      created_at: now
    }
  end

  defp persistent_subscription(%Subscription{} = subscription, %State{} = state) do
    %Subscription{name: subscription_name} = subscription
    %State{name: name, persistent_subscriptions: subscriptions} = state

    subscription_spec = subscription |> Subscription.child_spec() |> Map.put(:restart, :temporary)
    supervisor_name = subscriptions_name(name)

    {:ok, pid} = DynamicSupervisor.start_child(supervisor_name, subscription_spec)

    Process.monitor(pid)

    last_seen = start_from(subscription, state)

    subscription = %Subscription{subscription | subscriber: pid, last_seen: last_seen}

    catch_up(subscription, state)

    state = %State{
      state
      | persistent_subscriptions: Map.put(subscriptions, subscription_name, subscription)
    }

    {{:ok, pid}, state}
  end

  defp stop_subscription(subscription, %State{} = state) do
    %State{name: name} = state

    supervisor_name = subscriptions_name(name)

    DynamicSupervisor.terminate_child(supervisor_name, subscription)
  end

  defp remove_subscriber_by_pid(subscriptions, pid) do
    Enum.reduce(subscriptions, subscriptions, fn
      {name, %Subscription{subscriber: ^pid} = subscription}, acc ->
        Map.put(acc, name, %Subscription{subscription | subscriber: nil})

      _, acc ->
        acc
    end)
  end

  defp ack_subscription_by_pid(%RecordedEvent{} = event, pid, %State{} = state) do
    %State{persistent_subscriptions: subscriptions} = state

    %RecordedEvent{event_number: event_number} = event

    persistent_subscriptions =
      Enum.reduce(subscriptions, subscriptions, fn
        {name, %Subscription{subscriber: subscriber} = subscription}, acc
        when subscriber == pid ->
          subscription = %Subscription{subscription | last_seen: event_number}

          send_unseen_events(subscription, state)

          Map.put(acc, name, subscription)

        _, acc ->
          acc
      end)

    %State{state | persistent_subscriptions: persistent_subscriptions}
  end

  defp remove_transient_subscriber_by_pid(transient_subscriptions, pid) do
    Enum.reduce(transient_subscriptions, transient_subscriptions, fn
      {stream_uuid, subscribers}, transient ->
        Map.put(transient, stream_uuid, subscribers -- [pid])
    end)
  end

  defp start_from(%Subscription{last_seen: last_seen}, _state) when last_seen > 0, do: last_seen

  defp start_from(%Subscription{start_from: :origin}, _state), do: 0

  defp start_from(%Subscription{start_from: position}, _state) when is_integer(position),
    do: position

  defp start_from(%Subscription{start_from: :current, stream_uuid: :all}, %State{} = state) do
    %State{persisted_events: persisted_events} = state

    length(persisted_events)
  end

  defp start_from(%Subscription{start_from: :current} = subscription, %State{} = state) do
    %Subscription{stream_uuid: stream_uuid} = subscription
    %State{streams: streams} = state

    Map.get(streams, stream_uuid, []) |> length()
  end

  defp catch_up(%Subscription{start_from: :current}, _state), do: :ok

  defp catch_up(%Subscription{stream_uuid: :all} = subscription, %State{} = state) do
    send_unseen_events(subscription, state)
  end

  defp catch_up(%Subscription{} = subscription, %State{} = state) do
    send_unseen_events(subscription, state)
  end

  defp send_unseen_events(%Subscription{stream_uuid: :all} = subscription, %State{} = state) do
    %Subscription{subscriber: subscriber, last_seen: last_seen} = subscription
    %State{persisted_events: persisted_events} = state

    persisted_events
    |> Enum.reverse()
    |> Enum.drop(last_seen)
    |> Enum.map(&deserialize(&1, state))
    |> Enum.take(1)
    |> case do
      [] ->
        :ok

      unseen_events ->
        send(subscriber, {:events, unseen_events})
    end
  end

  defp send_unseen_events(%Subscription{} = subscription, %State{} = state) do
    %Subscription{subscriber: subscriber, stream_uuid: stream_uuid, last_seen: last_seen} =
      subscription

    %State{streams: streams} = state

    streams
    |> Map.get(stream_uuid, [])
    |> Enum.reverse()
    |> Enum.drop(last_seen)
    |> Enum.map(&deserialize(&1, state))
    |> set_event_number_from_version()
    |> Enum.take(1)
    |> case do
      [] ->
        :ok

      unseen_events ->
        send(subscriber, {:events, unseen_events})
    end
  end

  defp publish_to_transient_subscribers(stream_uuid, events, %State{} = state) do
    %State{transient_subscribers: transient} = state

    subscribers = Map.get(transient, stream_uuid, [])

    for subscriber <- subscribers |> Enum.filter(&is_pid/1) do
      send(subscriber, {:events, events})
    end
  end

  defp publish_to_persistent_subscriptions(:all, events, %State{} = state) do
    %State{persistent_subscriptions: subscriptions} = state
    [%RecordedEvent{event_number: event_number} = event | _events] = events

    for {_name, %Subscription{stream_uuid: :all} = subscription} <- subscriptions do
      %Subscription{subscriber: subscriber, last_seen: last_seen} = subscription

      if is_pid(subscriber) && (is_nil(last_seen) || event_number == last_seen + 1) do
        send(subscriber, {:events, [event]})
      end
    end
  end

  defp publish_to_persistent_subscriptions(stream_uuid, events, %State{} = state) do
    %State{persistent_subscriptions: subscriptions} = state
    [%RecordedEvent{stream_version: stream_version} = event | _events] = events

    for {_name, %Subscription{stream_uuid: ^stream_uuid} = subscription} <- subscriptions do
      %Subscription{subscriber: subscriber, last_seen: last_seen} = subscription

      if is_pid(subscriber) && (is_nil(last_seen) || stream_version == last_seen + 1) do
        send(subscriber, {:events, [event]})
      end
    end
  end

  defp serialize(data, %State{serializer: nil}), do: data

  defp serialize(%RecordedEvent{} = recorded_event, %State{} = state) do
    %RecordedEvent{data: data, metadata: metadata} = recorded_event
    %State{serializer: serializer} = state

    %RecordedEvent{
      recorded_event
      | data: serializer.serialize(data),
        metadata: serializer.serialize(metadata)
    }
  end

  defp serialize(%SnapshotData{} = snapshot, %State{} = state) do
    %SnapshotData{data: data, metadata: metadata} = snapshot
    %State{serializer: serializer} = state

    %SnapshotData{
      snapshot
      | data: serializer.serialize(data),
        metadata: serializer.serialize(metadata)
    }
  end

  defp deserialize(data, %State{serializer: nil}), do: data

  defp deserialize(%RecordedEvent{} = recorded_event, %State{} = state) do
    %RecordedEvent{data: data, metadata: metadata, event_type: event_type} = recorded_event
    %State{serializer: serializer} = state

    %RecordedEvent{
      recorded_event
      | data: serializer.deserialize(data, type: event_type),
        metadata: serializer.deserialize(metadata)
    }
  end

  defp deserialize(%SnapshotData{} = snapshot, %State{} = state) do
    %SnapshotData{data: data, metadata: metadata, source_type: source_type} = snapshot
    %State{serializer: serializer} = state

    %SnapshotData{
      snapshot
      | data: serializer.deserialize(data, type: source_type),
        metadata: serializer.deserialize(metadata)
    }
  end

  defp parse_config(application, config) do
    case Keyword.get(config, :name) do
      nil ->
        name = Module.concat([application, EventStore])

        {name, Keyword.put(config, :name, name)}

      name when is_atom(name) ->
        {name, config}

      invalid ->
        raise ArgumentError,
          message:
            "expected :name option to be an atom but got: " <>
              inspect(invalid)
    end
  end

  defp event_store_name(adapter_meta) when is_map(adapter_meta),
    do: Map.get(adapter_meta, :name)

  defp subscriptions_name(event_store),
    do: Module.concat([event_store, SubscriptionsSupervisor])
end
