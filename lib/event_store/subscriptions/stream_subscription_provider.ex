defmodule EventStore.Subscriptions.StreamSubscriptionProvider do
  @moduledoc """
  Specification to access subscription related event info from a single, or all streams
  """

  @type event :: EventStore.RecordedEvent.t
  @type subscription :: EventStore.Storage.Subscription.t
  @type stream_uuid :: String.t
  @type ack :: {event_id :: non_neg_integer(), stream_version :: non_neg_integer()}
  @type subscription_name :: String.t
  @type last_seen :: non_neg_integer()
  @type read_batch_size :: non_neg_integer()

  @doc """
  Get the last seen `event_id` or `stream_version` from the acknowledgement
  """
  @callback extract_ack(ack) :: non_neg_integer()

  @doc """
  Get the `event_id` or `stream_version` from the given event
  """
  @callback event_id(event) :: non_neg_integer()

  @doc """
  Get the last ack'd event for the given subscription
  """
  @callback last_ack(subscription) :: non_neg_integer()

  @doc """
  Get a stream of events since the last seen, fetched in batches limited to given size
  """
  @callback unseen_event_stream(stream_uuid, last_seen, read_batch_size) :: Enumerable.t

  @doc """
  Acknowledge receipt of the last seen event for the stream and subscription
  """
  @callback ack_last_seen_event(stream_uuid, subscription_name, last_seen) :: :ok | {:error, reason :: any()}
end
