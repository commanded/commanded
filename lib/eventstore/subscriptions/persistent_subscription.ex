defmodule EventStore.Subscriptions.PersistentSubscription do
  require Logger

  defmodule SubscriptionData do
    defstruct storage: nil,
              stream_uuid: nil,
              subscription_name: nil,
              subscriber: nil,
              last_seen_event_id: 0,
              latest_event_id: 0
  end

  alias EventStore.Storage
  alias EventStore.Subscriptions.PersistentSubscription

  use Fsm, initial_state: :initial, initial_data: %SubscriptionData{}

  defstate initial do
    defevent subscribe(storage, stream_uuid, subscription_name, subscriber), data: %SubscriptionData{} = data do
      case subscribe_to_stream(storage, stream_uuid, subscription_name) do
        {:ok, subscription} ->
          data = %SubscriptionData{data |
            storage: storage,
            stream_uuid: stream_uuid,
            subscription_name: subscription_name,
            subscriber: subscriber,
            last_seen_event_id: subscription.last_seen_event_id
          }
          next_state(:catching_up, data)
        {:error, reason} ->
          next_state(:failed, data)
      end
    end
  end

  defstate catching_up do
    defevent catch_up, data: %SubscriptionData{storage: storage, last_seen_event_id: last_seen_event_id} = data do
      case query_latest_event_id(storage) do
        0 -> next_state(:subscribed, data) # no published events
        ^last_seen_event_id -> next_state(:subscribed, data) # already seen latest published event
        latest_event_id ->
          # must catch-up with all unseen events
          data = catch_up_to_event(data, latest_event_id)
          next_state(:subscribed, data)
      end
    end

    defevent notify_events(events, latest_event_id), data: %SubscriptionData{} = data do
      # ignore event notification while catching up; but remember the latest event id
      data = %SubscriptionData{data | latest_event_id: latest_event_id}
      next_state(:catching_up, data)
    end
  end

  defstate subscribed do
    defevent notify_events(events, latest_event_id), data: %SubscriptionData{} = data do
      # TODO: move to catching-up state if the event id of the first event is not `data.last_seen_event_id + 1`
      # TODO: ack events

      data = %SubscriptionData{data |
        latest_event_id: latest_event_id,
        last_seen_event_id: latest_event_id
      }
      next_state(:subscribed, data)
    end

    defevent unsubscribe, data: %SubscriptionData{} = data do
      next_state(:unsubscribed, data)
    end
  end

  defstate unsubscribed do
  end

  defp subscribe_to_stream(storage, stream_uuid, subscription_name) do
    Storage.subscribe_to_stream(storage, stream_uuid, subscription_name)
  end

  defp query_latest_event_id(storage) do
    {:ok, latest_event_id} = Storage.latest_event_id(storage)
    latest_event_id
  end

  defp catch_up_to_event(%SubscriptionData{} = data, latest_event_id) do

    data = %SubscriptionData{data |
      latest_event_id: latest_event_id,
      last_seen_event_id: latest_event_id
    }
  end
end
