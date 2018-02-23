defmodule Commanded.EventStore.Adapters.InMemory do
  @moduledoc """
  An in-memory event store adapter useful for testing as no persistence provided.
  """

  @behaviour Commanded.EventStore

  use GenServer

  defmodule State do
    @moduledoc false

    defstruct [
      serializer: nil,
      persisted_events: [],
      streams: %{},
      transient_subscribers: %{},
      persistent_subscriptions: %{},
      snapshots: %{},
      next_event_number: 1
    ]
  end

  defmodule Subscription do
    @moduledoc false

    defstruct [
      name: nil,
      subscriber: nil,
      start_from: nil,
      last_seen_event_number: 0,
    ]
  end

  alias Commanded.EventStore.Adapters.InMemory.{
    State,
    Subscription,
  }

  alias Commanded.EventStore.{
    EventData,
    RecordedEvent,
    SnapshotData,
  }

  def start_link(opts \\ [])
  def start_link(opts) do
    state = %State{
      serializer: Keyword.get(opts, :serializer),
    }

    GenServer.start_link(__MODULE__, state, name: __MODULE__)
  end

  @impl GenServer
  def init(%State{} = state) do
    {:ok, state}
  end

  @impl Commanded.EventStore
  def append_to_stream(stream_uuid, expected_version, events) do
    GenServer.call(__MODULE__, {:append_to_stream, stream_uuid, expected_version, events})
  end

  @impl Commanded.EventStore
  def stream_forward(stream_uuid, start_version \\ 0, read_batch_size \\ 1_000)

  def stream_forward(stream_uuid, start_version, _read_batch_size) do
    GenServer.call(__MODULE__, {:stream_forward, stream_uuid, start_version})
  end

  @impl Commanded.EventStore
  def subscribe(stream_uuid) do
    GenServer.call(__MODULE__, {:subscribe, stream_uuid, self()})
  end

  @impl Commanded.EventStore
  def subscribe_to_all_streams(subscription_name, subscriber, start_from) do
    subscription = %Subscription{name: subscription_name, subscriber: subscriber, start_from: start_from}

    GenServer.call(__MODULE__, {:subscribe_to_all_streams, subscription})
  end

  @impl Commanded.EventStore
  def ack_event(pid, event) do
    GenServer.cast(__MODULE__, {:ack_event, event, pid})
  end

  @impl Commanded.EventStore
  def unsubscribe_from_all_streams(subscription_name) do
    GenServer.call(__MODULE__, {:unsubscribe_from_all_streams, subscription_name})
  end

  @impl Commanded.EventStore
  def read_snapshot(source_uuid) do
    GenServer.call(__MODULE__, {:read_snapshot, source_uuid})
  end

  @impl Commanded.EventStore
  def record_snapshot(snapshot) do
    GenServer.call(__MODULE__, {:record_snapshot, snapshot})
  end

  @impl Commanded.EventStore
  def delete_snapshot(source_uuid) do
    GenServer.call(__MODULE__, {:delete_snapshot, source_uuid})
  end

  @impl GenServer
  def handle_call({:append_to_stream, stream_uuid, expected_version, events}, _from, %State{streams: streams} = state) do
    case Map.get(streams, stream_uuid) do
      nil ->
        case expected_version do
          0 ->
            {reply, state} = persist_events(stream_uuid, [], events, state)

            {:reply, reply, state}
          _ -> {:reply, {:error, :wrong_expected_version}, state}
        end

      existing_events when length(existing_events) != expected_version ->
        {:reply, {:error, :wrong_expected_version}, state}

      existing_events ->
        {reply, state} = persist_events(stream_uuid, existing_events, events, state)

        {:reply, reply, state}
    end
  end

  @impl GenServer
  def handle_call({:stream_forward, stream_uuid, start_version}, _from, %State{streams: streams} = state) do
    reply = case Map.get(streams, stream_uuid) do
      nil -> {:error, :stream_not_found}
      events ->
        events
        |> Stream.drop(max(0, start_version - 1))
        |> Stream.map(&deserialize(&1, state))
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
  def handle_call({:subscribe_to_all_streams, %Subscription{name: subscription_name, subscriber: subscriber} = subscription}, _from, %State{persistent_subscriptions: subscriptions} = state) do
    {reply, state} = case Map.get(subscriptions, subscription_name) do
      nil ->
        state = persistent_subscription(subscription, state)

        {{:ok, subscriber}, state}

      %Subscription{subscriber: nil} = subscription ->
        state = persistent_subscription(%Subscription{subscription | subscriber: subscriber}, state)

        {{:ok, subscriber}, state}

      _subscription -> {{:error, :subscription_already_exists}, state}
    end

    {:reply, reply, state}
  end

  @impl GenServer
  def handle_call({:unsubscribe_from_all_streams, subscription_name}, _from, %State{persistent_subscriptions: subscriptions} = state) do
    state = %State{state |
      persistent_subscriptions: Map.delete(subscriptions, subscription_name),
    }

    {:reply, :ok, state}
  end

  @impl GenServer
  def handle_call({:read_snapshot, source_uuid}, _from, %State{snapshots: snapshots} = state) do
    reply = case Map.get(snapshots, source_uuid, nil) do
      nil -> {:error, :snapshot_not_found}
      snapshot -> {:ok, deserialize(snapshot, state)}
    end

    {:reply, reply, state}
  end

  @impl GenServer
  def handle_call({:record_snapshot, %SnapshotData{source_uuid: source_uuid} = snapshot}, _from, %State{snapshots: snapshots} = state) do
    state = %State{state |
      snapshots: Map.put(snapshots, source_uuid, serialize(snapshot, state)),
    }

    {:reply, :ok, state}
  end

  @impl GenServer
  def handle_call({:delete_snapshot, source_uuid}, _from, %State{snapshots: snapshots} = state) do
    state = %State{state |
      snapshots: Map.delete(snapshots, source_uuid)
    }

    {:reply, :ok, state}
  end

  @impl GenServer
  def handle_cast({:ack_event, event, subscriber}, %State{persistent_subscriptions: subscriptions} = state) do
    state = %State{state |
      persistent_subscriptions: ack_subscription_by_pid(subscriptions, event, subscriber),
    }

    {:noreply, state}
  end

  @impl GenServer
  def handle_info({:DOWN, _ref, :process, pid, _reason}, %State{} = state) do
    %State{persistent_subscriptions: persistent, transient_subscribers: transient} = state

    state = %State{state |
      persistent_subscriptions: remove_subscriber_by_pid(persistent, pid),
      transient_subscribers: remove_transient_subscriber_by_pid(transient, pid)
    }

    {:noreply, state}
  end

  defp persist_events(stream_uuid, existing_events, new_events, %State{persisted_events: persisted_events, streams: streams, next_event_number: next_event_number} = state) do
    initial_stream_version = length(existing_events) + 1
    now = NaiveDateTime.utc_now()

    new_events =
      new_events
      |> Enum.with_index(0)
      |> Enum.map(fn {recorded_event, index} ->
        event_number = next_event_number + index
        stream_version = initial_stream_version + index

        map_to_recorded_event(event_number, stream_uuid, stream_version, now, recorded_event)
      end)
      |> Enum.map(&serialize(&1, state))

    stream_events = Enum.concat(existing_events, new_events)
    next_event_number = List.last(new_events).event_number + 1

    state = %State{state |
      streams: Map.put(streams, stream_uuid, stream_events),
      persisted_events: [new_events | persisted_events],
      next_event_number: next_event_number,
    }

    publish_events = Enum.map(new_events, &deserialize(&1, state))

    publish_to_transient_subscribers(stream_uuid, publish_events, state)
    publish_to_persistent_subscriptions(publish_events, state)

    {{:ok, length(stream_events)}, state}
  end

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
      created_at: now,
    }
  end

  defp persistent_subscription(%Subscription{} = subscription, %State{} = state) do
    %Subscription{name: subscription_name, subscriber: subscriber} = subscription
    %State{persistent_subscriptions: subscriptions, persisted_events: persisted_events} = state

    Process.monitor(subscriber)

    send(subscriber, {:subscribed, subscriber})

    catch_up(subscription, persisted_events, state)

    %State{state |
      persistent_subscriptions: Map.put(subscriptions, subscription_name, subscription),
    }
  end

  defp remove_subscriber_by_pid(subscriptions, pid) do
    Enum.reduce(subscriptions, subscriptions, fn
      ({name, %Subscription{subscriber: subscriber} = subscription}, acc) when subscriber == pid -> Map.put(acc, name, %Subscription{subscription | subscriber: nil})
      (_, acc) -> acc
    end)
  end

  defp ack_subscription_by_pid(subscriptions, %RecordedEvent{event_number: event_number}, pid) do
    Enum.reduce(subscriptions, subscriptions, fn
      ({name, %Subscription{subscriber: subscriber} = subscription}, acc) when subscriber == pid -> Map.put(acc, name, %Subscription{subscription | last_seen_event_number: event_number})
      (_, acc) -> acc
    end)
  end

  defp remove_transient_subscriber_by_pid(transient_subscriptions, pid) do
    Enum.reduce(transient_subscriptions, transient_subscriptions, fn
      {stream_uuid, subscribers}, transient ->
        Map.put(transient, stream_uuid, subscribers -- [pid])
    end)
  end

  defp catch_up(%Subscription{subscriber: nil}, _persisted_events, _state), do: :ok
  defp catch_up(%Subscription{start_from: :current}, _persisted_events, _state), do: :ok
  defp catch_up(%Subscription{subscriber: subscriber, start_from: :origin, last_seen_event_number: last_seen_event_number}, persisted_events, %State{} = state) do
    unseen_events =
      persisted_events
      |> Enum.reverse()
      |> Enum.drop(last_seen_event_number)

    for events <- unseen_events,
      do: send(subscriber, {:events, Enum.map(events, &deserialize(&1, state))})
  end

  defp publish_to_transient_subscribers(stream_uuid, events, %State{transient_subscribers: transient}) do
    subscribers = Map.get(transient, stream_uuid, [])

    for subscriber <- subscribers |> Enum.filter(&is_pid/1) do
      send(subscriber, {:events, events})
    end
  end

  # publish events to subscribers
  defp publish_to_persistent_subscriptions(events, %State{persistent_subscriptions: subscriptions}) do
    subscribers =
      subscriptions
      |> Map.values()
      |> Enum.map(&(&1.subscriber))
      |> Enum.filter(&is_pid/1)

    for subscriber <- subscribers,
      do: send(subscriber, {:events, events})
  end

  defp serialize(data, %State{serializer: nil}), do: data
  defp serialize(%RecordedEvent{data: data, metadata: metadata} = recorded_event, %State{serializer: serializer}) do
    %RecordedEvent{recorded_event |
      data: serializer.serialize(data),
      metadata: serializer.serialize(metadata),
    }
  end
  defp serialize(%SnapshotData{data: data, metadata: metadata} = snapshot, %State{serializer: serializer}) do
    %SnapshotData{snapshot |
      data: serializer.serialize(data),
      metadata: serializer.serialize(metadata),
    }
  end

  def deserialize(data, %State{serializer: nil}), do: data
  def deserialize(%RecordedEvent{data: data, metadata: metadata, event_type: event_type} = recorded_event, %State{serializer: serializer}) do
    %RecordedEvent{recorded_event |
      data: serializer.deserialize(data, type: event_type),
      metadata: serializer.deserialize(metadata)
    }
  end
  def deserialize(%SnapshotData{data: data, metadata: metadata, source_type: source_type} = snapshot, %State{serializer: serializer}) do
    %SnapshotData{snapshot |
      data: serializer.deserialize(data, type: source_type),
      metadata: serializer.deserialize(metadata)
    }
  end
end
