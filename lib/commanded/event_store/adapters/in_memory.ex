defmodule Commanded.EventStore.Adapters.InMemory do
  @moduledoc """
  An in-memory event store adapter implemented as a `GenServer` process which
  stores events in memory only.

  This is only designed for testing purposes.
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

  alias Commanded.EventStore.Adapters.InMemory.{PersistentSubscription, State, Subscription}
  alias Commanded.EventStore.{EventData, RecordedEvent, SnapshotData}
  alias Commanded.UUID

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

    supervisor_name = subscriptions_supervisor_name(event_store_name)

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
  def stream_forward(adapter_meta, stream_uuid, start_version \\ 0, read_batch_size \\ 1_000)

  def stream_forward(adapter_meta, stream_uuid, start_version, _read_batch_size) do
    event_store = event_store_name(adapter_meta)

    GenServer.call(event_store, {:stream_forward, stream_uuid, start_version})
  end

  @impl Commanded.EventStore.Adapter
  def subscribe(adapter_meta, stream_uuid) do
    event_store = event_store_name(adapter_meta)

    GenServer.call(event_store, {:subscribe, stream_uuid, self()})
  end

  @impl Commanded.EventStore.Adapter
  def subscribe_to(adapter_meta, stream_uuid, subscription_name, subscriber, start_from, opts) do
    event_store = event_store_name(adapter_meta)

    subscription = %PersistentSubscription{
      concurrency_limit: Keyword.get(opts, :concurrency_limit),
      name: subscription_name,
      partition_by: Keyword.get(opts, :partition_by),
      start_from: start_from,
      stream_uuid: stream_uuid
    }

    GenServer.call(event_store, {:subscribe_to, subscription, subscriber})
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
  def handle_call({:append, stream_uuid, expected_version, events}, _from, %State{} = state) do
    %State{streams: streams} = state

    stream_events = Map.get(streams, stream_uuid)

    {reply, state} =
      case {expected_version, stream_events} do
        {:any_version, nil} ->
          persist_events(state, stream_uuid, [], events)

        {:any_version, stream_events} ->
          persist_events(state, stream_uuid, stream_events, events)

        {:no_stream, stream_events} when is_list(stream_events) ->
          {{:error, :stream_exists}, state}

        {:no_stream, nil} ->
          persist_events(state, stream_uuid, [], events)

        {:stream_exists, nil} ->
          {{:error, :stream_not_found}, state}

        {:stream_exists, stream_events} ->
          persist_events(state, stream_uuid, stream_events, events)

        {0, nil} ->
          persist_events(state, stream_uuid, [], events)

        {expected_version, nil} when is_integer(expected_version) ->
          {{:error, :wrong_expected_version}, state}

        {expected_version, stream_events}
        when is_integer(expected_version) and length(stream_events) != expected_version ->
          {{:error, :wrong_expected_version}, state}

        {expected_version, stream_events}
        when is_integer(expected_version) and length(stream_events) == expected_version ->
          persist_events(state, stream_uuid, stream_events, events)
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
          |> Stream.map(&deserialize(state, &1))
          |> Enum.map(&set_event_number_from_version(&1, stream_uuid))
      end

    {:reply, reply, state}
  end

  @impl GenServer
  def handle_call({:subscribe, stream_uuid, subscriber}, _from, %State{} = state) do
    %State{transient_subscribers: transient_subscribers} = state

    Process.monitor(subscriber)

    transient_subscribers =
      Map.update(transient_subscribers, stream_uuid, [subscriber], fn subscribers ->
        [subscriber | subscribers]
      end)

    state = %State{state | transient_subscribers: transient_subscribers}

    {:reply, :ok, state}
  end

  @impl GenServer
  def handle_call({:subscribe_to, subscription, subscriber}, _from, %State{} = state) do
    %PersistentSubscription{name: subscription_name} = subscription
    %State{persistent_subscriptions: persistent_subscriptions} = state

    {reply, state} =
      case Map.get(persistent_subscriptions, subscription_name) do
        nil ->
          start_persistent_subscription(state, subscription, subscriber)

        %PersistentSubscription{subscribers: []} = subscription ->
          start_persistent_subscription(state, subscription, subscriber)

        %PersistentSubscription{concurrency_limit: nil} ->
          {{:error, :subscription_already_exists}, state}

        %PersistentSubscription{} = subscription ->
          %PersistentSubscription{concurrency_limit: concurrency_limit, subscribers: subscribers} =
            subscription

          if length(subscribers) < concurrency_limit do
            start_persistent_subscription(state, subscription, subscriber)
          else
            {{:error, :too_many_subscribers}, state}
          end
      end

    {:reply, reply, state}
  end

  @impl GenServer
  def handle_call({:unsubscribe, pid}, _from, %State{} = state) do
    state =
      update_persistent_subscription(state, pid, fn %PersistentSubscription{} = subscription ->
        :ok = stop_subscription(state, pid)

        PersistentSubscription.unsubscribe(subscription, pid)
      end)

    {:reply, :ok, state}
  end

  @impl GenServer
  def handle_call({:delete_subscription, stream_uuid, subscription_name}, _from, %State{} = state) do
    %State{persistent_subscriptions: persistent_subscriptions} = state

    {reply, state} =
      case Map.get(persistent_subscriptions, subscription_name) do
        %PersistentSubscription{stream_uuid: ^stream_uuid, subscribers: []} ->
          state = %State{
            state
            | persistent_subscriptions: Map.delete(persistent_subscriptions, subscription_name)
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
        snapshot -> {:ok, deserialize(state, snapshot)}
      end

    {:reply, reply, state}
  end

  @impl GenServer
  def handle_call({:record_snapshot, %SnapshotData{} = snapshot}, _from, %State{} = state) do
    %SnapshotData{source_uuid: source_uuid} = snapshot
    %State{snapshots: snapshots} = state

    state = %State{state | snapshots: Map.put(snapshots, source_uuid, serialize(state, snapshot))}

    {:reply, :ok, state}
  end

  @impl GenServer
  def handle_call({:delete_snapshot, source_uuid}, _from, %State{} = state) do
    %State{snapshots: snapshots} = state

    state = %State{state | snapshots: Map.delete(snapshots, source_uuid)}

    {:reply, :ok, state}
  end

  @impl GenServer
  def handle_call(:reset!, _from, %State{} = state) do
    %State{name: name, serializer: serializer, persistent_subscriptions: persistent_subscriptions} =
      state

    for {_name, %PersistentSubscription{subscribers: subscribers}} <- persistent_subscriptions do
      for %{pid: pid} <- subscribers, is_pid(pid) do
        stop_subscription(state, pid)
      end
    end

    initial_state = %State{name: name, serializer: serializer}

    {:reply, :ok, initial_state}
  end

  @impl GenServer
  def handle_call({:ack_event, event, subscriber}, _from, %State{} = state) do
    state = ack_persistent_subscription_by_pid(state, event, subscriber)

    {:reply, :ok, state}
  end

  @impl GenServer
  def handle_info({:DOWN, _ref, :process, pid, _reason}, %State{} = state) do
    state =
      state
      |> remove_persistent_subscription_by_pid(pid)
      |> remove_transient_subscriber_by_pid(pid)

    {:noreply, state}
  end

  defp persist_events(%State{} = state, stream_uuid, existing_events, new_events) do
    %State{
      next_event_number: next_event_number,
      persisted_events: persisted_events,
      persistent_subscriptions: persistent_subscriptions,
      streams: streams
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
      |> Enum.map(&serialize(state, &1))

    stream_events = prepend(existing_events, new_events)
    next_event_number = List.last(new_events).event_number + 1

    state = %State{
      state
      | streams: Map.put(streams, stream_uuid, stream_events),
        persisted_events: prepend(persisted_events, new_events),
        next_event_number: next_event_number
    }

    publish_all_events = Enum.map(new_events, &deserialize(state, &1))

    publish_stream_events =
      Enum.map(publish_all_events, &set_event_number_from_version(&1, stream_uuid))

    state = publish_to_transient_subscribers(state, :all, publish_all_events)
    state = publish_to_transient_subscribers(state, stream_uuid, publish_stream_events)

    persistent_subscriptions =
      Enum.into(persistent_subscriptions, %{}, fn {subscription_name, subscription} ->
        {subscription_name, publish_events(state, subscription)}
      end)

    state = %State{state | persistent_subscriptions: persistent_subscriptions}

    {:ok, state}
  end

  defp set_event_number_from_version(%RecordedEvent{} = event, :all), do: event

  # Event number should equal stream version for stream events.
  defp set_event_number_from_version(%RecordedEvent{} = event, _stream_uuid) do
    %RecordedEvent{stream_version: stream_version} = event

    %RecordedEvent{event | event_number: stream_version}
  end

  defp prepend(list, []), do: list
  defp prepend(list, [item | remainder]), do: prepend([item | list], remainder)

  defp map_to_recorded_event(event_number, stream_uuid, stream_version, now, %EventData{} = event) do
    %EventData{
      causation_id: causation_id,
      correlation_id: correlation_id,
      event_type: event_type,
      data: data,
      metadata: metadata
    } = event

    %RecordedEvent{
      event_id: UUID.uuid4(),
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

  defp start_persistent_subscription(%State{} = state, subscription, subscriber) do
    %State{name: event_store_name, persistent_subscriptions: persistent_subscriptions} = state
    %PersistentSubscription{name: subscription_name, checkpoint: checkpoint} = subscription

    supervisor_name = subscriptions_supervisor_name(event_store_name)
    subscription_spec = Subscription.child_spec(subscriber) |> Map.put(:restart, :temporary)

    {:ok, pid} = DynamicSupervisor.start_child(supervisor_name, subscription_spec)

    Process.monitor(pid)

    checkpoint = if is_nil(checkpoint), do: start_from(state, subscription), else: checkpoint

    subscription = PersistentSubscription.subscribe(subscription, pid, checkpoint)
    subscription = publish_events(state, subscription)

    persistent_subscriptions = Map.put(persistent_subscriptions, subscription_name, subscription)

    state = %State{state | persistent_subscriptions: persistent_subscriptions}

    {{:ok, pid}, state}
  end

  defp publish_events(%State{} = state, %PersistentSubscription{} = subscription) do
    %State{persisted_events: persisted_events, streams: streams} = state
    %PersistentSubscription{checkpoint: checkpoint, stream_uuid: stream_uuid} = subscription

    events =
      case stream_uuid do
        :all -> persisted_events
        stream_uuid -> Map.get(streams, stream_uuid, [])
      end

    position = if checkpoint == 0, do: -1, else: -(checkpoint + 1)

    case Enum.at(events, position) do
      %RecordedEvent{} = unseen_event ->
        unseen_event =
          deserialize(state, unseen_event) |> set_event_number_from_version(stream_uuid)

        case PersistentSubscription.publish(subscription, unseen_event) do
          {:ok, subscription} -> publish_events(state, subscription)
          {:error, :no_subscriber_available} -> subscription
        end

      nil ->
        subscription
    end
  end

  defp stop_subscription(%State{} = state, subscription) do
    %State{name: name} = state

    supervisor_name = subscriptions_supervisor_name(name)

    DynamicSupervisor.terminate_child(supervisor_name, subscription)
  end

  defp ack_persistent_subscription_by_pid(%State{} = state, %RecordedEvent{} = event, pid) do
    %RecordedEvent{event_number: event_number} = event

    update_persistent_subscription(state, pid, fn %PersistentSubscription{} = subscription ->
      subscription = PersistentSubscription.ack(subscription, event_number)

      publish_events(state, subscription)
    end)
  end

  defp remove_persistent_subscription_by_pid(%State{} = state, pid) do
    update_persistent_subscription(state, pid, fn %PersistentSubscription{} = subscription ->
      subscription = PersistentSubscription.unsubscribe(subscription, pid)

      publish_events(state, subscription)
    end)
  end

  defp update_persistent_subscription(%State{} = state, pid, updater)
       when is_function(updater, 1) do
    %State{persistent_subscriptions: persistent_subscriptions} = state

    case find_persistent_subscription(persistent_subscriptions, pid) do
      {subscription_name, %PersistentSubscription{} = subscription} ->
        updated_subscription = updater.(subscription)

        persistent_subscriptions =
          Map.put(persistent_subscriptions, subscription_name, updated_subscription)

        %State{state | persistent_subscriptions: persistent_subscriptions}

      _ ->
        state
    end
  end

  defp find_persistent_subscription(persistent_subscriptions, pid) do
    Enum.find(persistent_subscriptions, fn {_name, %PersistentSubscription{} = subscription} ->
      PersistentSubscription.has_subscriber?(subscription, pid)
    end)
  end

  defp remove_transient_subscriber_by_pid(%State{} = state, pid) do
    %State{transient_subscribers: transient_subscribers} = state

    transient_subscribers =
      Enum.reduce(transient_subscribers, transient_subscribers, fn
        {stream_uuid, subscribers}, acc ->
          Map.put(acc, stream_uuid, List.delete(subscribers, pid))
      end)

    %State{state | transient_subscribers: transient_subscribers}
  end

  defp start_from(%State{} = state, %PersistentSubscription{} = subscription) do
    %State{persisted_events: persisted_events, streams: streams} = state
    %PersistentSubscription{start_from: start_from, stream_uuid: stream_uuid} = subscription

    case {start_from, stream_uuid} do
      {:current, :all} -> length(persisted_events)
      {:current, stream_uuid} -> Map.get(streams, stream_uuid, []) |> length()
      {:origin, _stream_uuid} -> 0
      {position, _stream_uuid} when is_integer(position) -> position
    end
  end

  defp publish_to_transient_subscribers(%State{} = state, stream_uuid, events) do
    %State{transient_subscribers: transient_subscribers} = state

    subscribers = Map.get(transient_subscribers, stream_uuid, [])

    for subscriber <- subscribers, &is_pid/1 do
      send(subscriber, {:events, events})
    end

    state
  end

  defp serialize(%State{serializer: nil}, data), do: data

  defp serialize(%State{} = state, %RecordedEvent{} = recorded_event) do
    %State{serializer: serializer} = state
    %RecordedEvent{data: data, metadata: metadata} = recorded_event

    %RecordedEvent{
      recorded_event
      | data: serializer.serialize(data),
        metadata: serializer.serialize(metadata)
    }
  end

  defp serialize(%State{} = state, %SnapshotData{} = snapshot) do
    %State{serializer: serializer} = state
    %SnapshotData{data: data, metadata: metadata} = snapshot

    %SnapshotData{
      snapshot
      | data: serializer.serialize(data),
        metadata: serializer.serialize(metadata)
    }
  end

  defp deserialize(%State{serializer: nil}, data), do: data

  defp deserialize(%State{} = state, %RecordedEvent{} = recorded_event) do
    %State{serializer: serializer} = state
    %RecordedEvent{data: data, metadata: metadata, event_type: event_type} = recorded_event

    %RecordedEvent{
      recorded_event
      | data: serializer.deserialize(data, type: event_type),
        metadata: serializer.deserialize(metadata)
    }
  end

  defp deserialize(%State{} = state, %SnapshotData{} = snapshot) do
    %State{serializer: serializer} = state
    %SnapshotData{data: data, metadata: metadata, source_type: source_type} = snapshot

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

  defp subscriptions_supervisor_name(event_store),
    do: Module.concat([event_store, SubscriptionsSupervisor])
end
