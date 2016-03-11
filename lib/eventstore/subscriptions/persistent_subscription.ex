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

  @all_stream "$all"

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
        0 ->
          # no published events
          next_state(:subscribed, data)

        ^last_seen_event_id ->
          # already seen latest published event
          next_state(:subscribed, data)

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
    defevent notify_events(events), data: %SubscriptionData{} = data do
      # TODO: move to catching-up state if the event id of the first event is not `data.last_seen_event_id + 1`

      latest_event_id = List.last(events).event_id

      notify_subscriber(data, events)
      ack_events(data, events)

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

  defp catch_up_to_event(%SubscriptionData{storage: storage, stream_uuid: stream_uuid, last_seen_event_id: last_seen_event_id} = data, latest_event_id) do
    case unseen_events(data) do
      {:ok, events} ->
        # chunk events by stream
        events
        |> Enum.chunk_by(fn event -> event.stream_id end)
        |> Enum.each(fn events_by_stream ->
          notify_subscriber(data, events_by_stream)
          ack_events(data, events_by_stream)
        end)
    end

    data = %SubscriptionData{data |
      latest_event_id: latest_event_id,
      last_seen_event_id: latest_event_id
    }
  end

  defp unseen_events(%SubscriptionData{storage: storage, stream_uuid: @all_stream, last_seen_event_id: last_seen_event_id}) do
    start_event_id = last_seen_event_id + 1

    Storage.read_all_streams_forward(storage, start_event_id)
  end

  defp unseen_events(%SubscriptionData{storage: storage, stream_uuid: stream_uuid, last_seen_event_id: last_seen_event_id}) do
    start_version = last_seen_event_id + 1

    Storage.read_stream_forward(storage, stream_uuid, start_version)
  end

  defp notify_subscriber(%SubscriptionData{subscriber: subscriber} = data, events) do
    send(subscriber, {:events, events})
  end

  defp ack_events(%SubscriptionData{} = data, events) do

  end
end
