defmodule EventStore.Subscriptions.SubscriptionState do
  defstruct [
    stream_uuid: nil,
    stream: nil,
    subscription_name: nil,
    subscriber: nil,
    mapper: nil,
    last_seen: 0,
    last_ack: 0,
    pending_events: [],
    max_size: nil,
  ]
end
