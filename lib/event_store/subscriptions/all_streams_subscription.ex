defmodule EventStore.Subscriptions.AllStreamsSubscription do
  @behaviour EventStore.Subscriptions.StreamSubscriptionProvider

  alias EventStore.{RecordedEvent,Storage}
  alias EventStore.Streams.AllStream
  alias EventStore.Subscriptions.StreamSubscriptionProvider

  @all_stream "$all"

  def extract_ack({event_id, _stream_version}), do: event_id

  def event_id(%RecordedEvent{event_id: event_id}), do: event_id

  def last_ack(%Storage.Subscription{last_seen_event_id: last_seen_event_id}) do
    last_seen_event_id
  end

  def unseen_event_stream(@all_stream, last_seen, read_batch_size) do
    AllStream.stream_forward(last_seen + 1, read_batch_size)
  end

  def ack_last_seen_event(@all_stream, subscription_name, last_event_id) do
    Storage.ack_last_seen_event(@all_stream, subscription_name, last_event_id, nil)
  end
end
