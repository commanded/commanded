defmodule EventStore.Subscriptions.SingleStreamSubscription do
  alias EventStore.Storage
  alias EventStore.Streams.Stream

  def event_id(%EventStore.RecordedEvent{stream_version: stream_version}) do
    stream_version
  end

  def last_ack(%EventStore.Storage.Subscription{last_seen_stream_version: last_seen_stream_version}) do
    last_seen_stream_version
  end

  def state(stream) do
    Stream.stream_version(stream)
  end

  def unseen_events(stream, last_seen_stream_version) do
    start_version = last_seen_stream_version + 1

    Stream.read_stream_forward(stream, start_version, 1_000)
  end

  def ack_last_seen_event(stream_uuid, subscription_name, last_stream_version) do
    Storage.ack_last_seen_event(stream_uuid, subscription_name, nil, last_stream_version)
  end
end
