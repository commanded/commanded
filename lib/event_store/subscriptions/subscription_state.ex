defmodule EventStore.Subscriptions.SubscriptionState do
  defstruct [
    catch_up_pid: nil,
    stream_uuid: nil,
    subscription_name: nil,
    subscriber: nil,
    mapper: nil,
    last_seen: 0,
    last_ack: 0,
    pending_events: [],
    max_size: nil,
  ]
end
