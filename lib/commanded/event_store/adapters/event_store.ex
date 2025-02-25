if Code.ensure_loaded?(EventStore) do
  defmodule Commanded.EventStore.Adapters.EventStore do
    @moduledoc """
    `EventStore` Adapter for Commanded.
    """

    alias EventStore.Subscriptions.Subscription

    @behaviour Commanded.EventStore.Adapter

    @all_stream "$all"

    @impl Commanded.EventStore.Adapter
    def child_spec(application, config) do
      {event_store, config} = Keyword.pop(config, :event_store)

      verify_event_store!(application, event_store)

      name = Keyword.get(config, :name, event_store)

      # Rename `prefix` config to `schema`
      config =
        case Keyword.pop(config, :prefix) do
          {nil, config} -> config
          {prefix, config} -> Keyword.put(config, :schema, prefix)
        end

      child_spec = [{event_store, config}]
      adapter_meta = %{event_store: event_store, name: name}

      {:ok, child_spec, adapter_meta}
    end

    @impl Commanded.EventStore.Adapter
    def append_to_stream(adapter_meta, stream_uuid, expected_version, events, opts \\ []) do
      {event_store, name} = extract_adapter_meta(adapter_meta)

      events = Enum.map(events, &to_event_data/1)

      opts = Keyword.put(opts, :name, name)
      event_store.append_to_stream(stream_uuid, expected_version, events, opts)
    end

    @impl Commanded.EventStore.Adapter
    def stream_forward(adapter_meta, stream_uuid, start_version \\ 0, read_batch_size \\ 1_000) do
      {event_store, name} = extract_adapter_meta(adapter_meta)

      opts = [name: name, read_batch_size: read_batch_size]

      case event_store.stream_forward(stream_uuid, start_version, opts) do
        {:error, error} -> {:error, error}
        stream -> Stream.map(stream, &from_recorded_event/1)
      end
    end

    @impl Commanded.EventStore.Adapter
    def subscribe(adapter_meta, :all), do: subscribe(adapter_meta, @all_stream)

    @impl Commanded.EventStore.Adapter
    def subscribe(adapter_meta, stream_uuid) do
      {event_store, name} = extract_adapter_meta(adapter_meta)

      event_store.subscribe(stream_uuid, name: name, mapper: &from_recorded_event/1)
    end

    @impl Commanded.EventStore.Adapter
    def subscribe_to(adapter_meta, :all, subscription_name, subscriber, start_from, opts) do
      {event_store, name} = extract_adapter_meta(adapter_meta)

      event_store.subscribe_to_all_streams(
        subscription_name,
        subscriber,
        subscription_options(name, start_from, opts)
      )
    end

    @impl Commanded.EventStore.Adapter
    def subscribe_to(adapter_meta, stream_uuid, subscription_name, subscriber, start_from, opts) do
      {event_store, name} = extract_adapter_meta(adapter_meta)

      event_store.subscribe_to_stream(
        stream_uuid,
        subscription_name,
        subscriber,
        subscription_options(name, start_from, opts)
      )
    end

    @impl Commanded.EventStore.Adapter
    def ack_event(adapter_meta, subscription, %Commanded.EventStore.RecordedEvent{} = event) do
      %Commanded.EventStore.RecordedEvent{event_number: event_number} = event

      {event_store, _name} = extract_adapter_meta(adapter_meta)

      event_store.ack(subscription, event_number)
    end

    @impl Commanded.EventStore.Adapter
    def unsubscribe(_adapter_meta, subscription) do
      Subscription.unsubscribe(subscription)
    end

    @impl Commanded.EventStore.Adapter
    def delete_subscription(adapter_meta, :all, subscription_name) do
      {event_store, name} = extract_adapter_meta(adapter_meta)

      event_store.delete_subscription(@all_stream, subscription_name, name: name)
    end

    @impl Commanded.EventStore.Adapter
    def delete_subscription(adapter_meta, stream_uuid, subscription_name) do
      {event_store, name} = extract_adapter_meta(adapter_meta)

      event_store.delete_subscription(stream_uuid, subscription_name, name: name)
    end

    @impl Commanded.EventStore.Adapter
    def read_snapshot(adapter_meta, source_uuid) do
      {event_store, name} = extract_adapter_meta(adapter_meta)

      with {:ok, snapshot_data} <- event_store.read_snapshot(source_uuid, name: name) do
        snapshot = from_snapshot_data(snapshot_data)

        {:ok, snapshot}
      end
    end

    @impl Commanded.EventStore.Adapter
    def record_snapshot(adapter_meta, %Commanded.EventStore.SnapshotData{} = snapshot) do
      {event_store, name} = extract_adapter_meta(adapter_meta)

      snapshot
      |> to_snapshot_data()
      |> event_store.record_snapshot(name: name)
    end

    @impl Commanded.EventStore.Adapter
    def delete_snapshot(adapter_meta, source_uuid) do
      {event_store, name} = extract_adapter_meta(adapter_meta)

      event_store.delete_snapshot(source_uuid, name: name)
    end

    defp subscription_options(name, start_from, opts) do
      opts
      |> Keyword.merge(
        name: name,
        start_from: start_from,
        mapper: &from_recorded_event/1
      )
      |> Keyword.update(:partition_by, nil, fn
        nil ->
          nil

        partition_by when is_function(partition_by, 1) ->
          fn %EventStore.RecordedEvent{} = event ->
            from_recorded_event(event) |> partition_by.()
          end
      end)
    end

    defp extract_adapter_meta(adapter_meta) do
      event_store = Map.fetch!(adapter_meta, :event_store)
      name = Map.fetch!(adapter_meta, :name)

      {event_store, name}
    end

    defp verify_event_store!(application, event_store) do
      unless event_store do
        raise ArgumentError,
              "missing :event_store option for event store adapter in application " <>
                inspect(application)
      end

      unless implements?(event_store, EventStore) do
        raise ArgumentError,
              "module " <>
                inspect(event_store) <>
                " is not an EventStore, " <>
                "ensure you pass an event store module to the :event_store config in application " <>
                inspect(application)
      end
    end

    # Returns `true` if module implements behaviour.
    defp implements?(module, behaviour) do
      behaviours = Keyword.take(module.__info__(:attributes), [:behaviour])

      [behaviour] in Keyword.values(behaviours)
    end

    defp to_event_data(%Commanded.EventStore.EventData{} = event_data) do
      %Commanded.EventStore.EventData{
        causation_id: causation_id,
        correlation_id: correlation_id,
        event_type: event_type,
        data: data,
        metadata: metadata,
        event_id: event_id
      } = event_data

      %EventStore.EventData{
        causation_id: causation_id,
        correlation_id: correlation_id,
        event_type: event_type,
        data: data,
        metadata: metadata,
        event_id: event_id
      }
    end

    defp from_recorded_event(%EventStore.RecordedEvent{} = event) do
      %EventStore.RecordedEvent{
        event_id: event_id,
        event_number: event_number,
        stream_uuid: stream_uuid,
        stream_version: stream_version,
        correlation_id: correlation_id,
        causation_id: causation_id,
        event_type: event_type,
        data: data,
        metadata: metadata,
        created_at: created_at
      } = event

      %Commanded.EventStore.RecordedEvent{
        event_id: event_id,
        event_number: event_number,
        stream_id: stream_uuid,
        stream_version: stream_version,
        correlation_id: correlation_id,
        causation_id: causation_id,
        event_type: event_type,
        data: data,
        metadata: metadata,
        created_at: created_at
      }
    end

    defp to_snapshot_data(%Commanded.EventStore.SnapshotData{} = snapshot) do
      %Commanded.EventStore.SnapshotData{
        source_uuid: source_uuid,
        source_version: source_version,
        source_type: source_type,
        data: data,
        metadata: metadata,
        created_at: created_at
      } = snapshot

      %EventStore.Snapshots.SnapshotData{
        source_uuid: source_uuid,
        source_version: source_version,
        source_type: source_type,
        data: data,
        metadata: metadata,
        created_at: created_at
      }
    end

    defp from_snapshot_data(%EventStore.Snapshots.SnapshotData{} = snapshot) do
      %EventStore.Snapshots.SnapshotData{
        source_uuid: source_uuid,
        source_version: source_version,
        source_type: source_type,
        data: data,
        metadata: metadata,
        created_at: created_at
      } = snapshot

      %Commanded.EventStore.SnapshotData{
        source_uuid: source_uuid,
        source_version: source_version,
        source_type: source_type,
        data: data,
        metadata: metadata,
        created_at: created_at
      }
    end
  end
end
