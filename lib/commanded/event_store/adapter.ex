defmodule Commanded.EventStore.Adapter do
  @moduledoc false

  alias Commanded.EventStore
  alias Commanded.EventStore.{EventData, RecordedEvent, SnapshotData}

  def child_spec(adapter, application, config) do
    adapter.child_spec(application, config)
  end

  def append_to_stream(adapter, event_store, stream_uuid, expected_version, events)
      when is_binary(stream_uuid) and
             (is_integer(expected_version) or
                expected_version in [:any_version, :no_stream, :stream_exists]) and
             is_list(events) do
    adapter.append_to_stream(event_store, stream_uuid, expected_version, events)
  end

  def stream_forward(
        event_store_adapter,
        stream_uuid,
        start_version \\ 0,
        read_batch_size \\ 1_000
      )
      when is_binary(stream_uuid) and is_integer(start_version) and is_integer(read_batch_size) do
    alias Commanded.Event.Upcast

    case event_store_adapter.stream_forward(stream_uuid, start_version, read_batch_size) do
      {:error, _} = error -> error
      stream -> Upcast.upcast_event_stream(stream)
    end
  end

  def subscribe(event_store_adapter, stream_uuid)
      when stream_uuid == :all or is_binary(stream_uuid) do
    event_store_adapter.subscribe(stream_uuid)
  end

  def subscribe_to(event_store_adapter, stream_uuid, subscription_name, subscriber, start_from)
      when is_binary(subscription_name) and is_pid(subscriber) do
    event_store_adapter.subscribe_to(stream_uuid, subscription_name, subscriber, start_from)
  end

  def ack_event(event_store_adapter, pid, %RecordedEvent{} = event) when is_pid(pid) do
    event_store_adapter.ack_event(pid, event)
  end

  def unsubscribe(event_store_adapter, subscription) do
    event_store_adapter.unsubscribe(subscription)
  end

  def delete_subscription(event_store_adapter, stream_uuid, subscription_name) do
    event_store_adapter.delete_subscription(stream_uuid, subscription_name)
  end

  def read_snapshot(event_store_adapter, source_uuid) when is_binary(source_uuid) do
    event_store_adapter.read_snapshot(source_uuid)
  end

  def record_snapshot(event_store_adapter, %SnapshotData{} = snapshot) do
    event_store_adapter.record_snapshot(snapshot)
  end

  def delete_snapshot(event_store_adapter, source_uuid) when is_binary(source_uuid) do
    event_store_adapter.delete_snapshot(source_uuid)
  end
end
