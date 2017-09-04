defmodule EventStore.Subscriptions.AllStreamsSubscription do
  @moduledoc false
  @behaviour EventStore.Subscriptions.StreamSubscriptionProvider

  alias EventStore.Storage
  alias EventStore.Streams.AllStream

  @all_stream "$all"

  def event_id(%EventStore.RecordedEvent{event_id: event_id}) do
    event_id
  end

  def last_ack(%EventStore.Storage.Subscription{last_seen_event_id: last_seen_event_id}) do
    last_seen_event_id
  end

  def unseen_event_stream(@all_stream, last_seen, read_batch_size) do
    AllStream.stream_forward(last_seen + 1, read_batch_size)
  end

  def ack_last_seen_event(@all_stream, subscription_name, last_event_id) do
    Storage.ack_last_seen_event(@all_stream, subscription_name, last_event_id, nil)
  end
end
