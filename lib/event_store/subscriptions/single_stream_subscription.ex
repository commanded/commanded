defmodule EventStore.Subscriptions.SingleStreamSubscription do
  @moduledoc false
  @behaviour EventStore.Subscriptions.StreamSubscriptionProvider

  alias EventStore.Storage
  alias EventStore.Streams.Stream

  def event_id(%EventStore.RecordedEvent{stream_version: stream_version}) do
    stream_version
  end

  def last_ack(%EventStore.Storage.Subscription{last_seen_stream_version: last_seen_stream_version}) do
    last_seen_stream_version
  end

  def unseen_event_stream(stream_uuid, last_seen, read_batch_size) do
    Stream.stream_forward(stream_uuid, last_seen + 1, read_batch_size)
  end

  def ack_last_seen_event(stream_uuid, subscription_name, last_stream_version) do
    Storage.ack_last_seen_event(stream_uuid, subscription_name, nil, last_stream_version)
  end
end
