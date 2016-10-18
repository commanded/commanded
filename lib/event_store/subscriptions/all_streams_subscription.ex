defmodule EventStore.Subscriptions.AllStreamsSubscription do
  alias EventStore.Storage
  alias EventStore.Streams.AllStream

  @all_stream "$all"

  def event_id(%EventStore.RecordedEvent{event_id: event_id}) do
    event_id
  end

  def last_ack(%EventStore.Storage.Subscription{last_seen_event_id: last_seen_event_id}) do
    last_seen_event_id
  end

  def unseen_events(_stream, last_seen_event_id, count) do
    start_event_id = last_seen_event_id + 1

    AllStream.read_stream_forward(start_event_id, count)
  end

  def ack_last_seen_event(@all_stream, subscription_name, last_event_id) do
    Storage.ack_last_seen_event(@all_stream, subscription_name, last_event_id, nil)
  end
end
