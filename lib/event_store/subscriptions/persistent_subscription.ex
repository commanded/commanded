defmodule EventStore.Subscriptions.PersistentSubscription do
  require Logger

  defmodule SubscriptionData do
    defstruct stream_uuid: nil,
              subscription_name: nil,
              subscriber: nil,
              last_seen_event_id: 0,
              last_seen_stream_version: 0,
              latest_event_id: 0
  end

  alias EventStore.{RecordedEvent,Storage}
  alias EventStore.Subscriptions.PersistentSubscription

  use Fsm, initial_state: :initial, initial_data: %SubscriptionData{}

  @all_stream "$all"

  defstate initial do
    defevent subscribe(stream_uuid, subscription_name, subscriber), data: %SubscriptionData{} = data do
      case subscribe_to_stream(stream_uuid, subscription_name) do
        {:ok, subscription} ->
          data = %SubscriptionData{data |
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
    defevent catch_up, data: %SubscriptionData{last_seen_event_id: last_seen_event_id} = data do
      case query_latest_event_id do
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

    # ignore event notifications while catching up; but remember the latest event id
    defevent notify_events(events, latest_event_id), data: %SubscriptionData{} = data do
      data = %SubscriptionData{data | latest_event_id: latest_event_id}
      next_state(:catching_up, data)
    end
  end

  defstate subscribed do
    defevent notify_events(events), data: %SubscriptionData{} = data do
      # TODO: move to catching-up state if the event id of the first event is not `data.last_seen_event_id + 1`

      last_event = List.last(events)

      notify_subscriber(data, events)
      ack_events(data, events, last_event.event_id)

      data = %SubscriptionData{data |
        latest_event_id: last_event.event_id,
        last_seen_event_id: last_event.event_id,
        last_seen_stream_version: last_event.stream_version
      }

      next_state(:subscribed, data)
    end

    defevent unsubscribe, data: %SubscriptionData{} = data do
      next_state(:unsubscribed, data)
    end
  end

  defstate unsubscribed do
  end

  defstate failed do
  end

  defp subscribe_to_stream(stream_uuid, subscription_name) do
    Storage.subscribe_to_stream(stream_uuid, subscription_name)
  end

  defp query_latest_event_id do
    {:ok, latest_event_id} = Storage.latest_event_id
    latest_event_id
  end

  defp catch_up_to_event(%SubscriptionData{stream_uuid: stream_uuid, last_seen_event_id: last_seen_event_id} = data, latest_event_id) do
    last_event = case unseen_events(data) do
      {:ok, events} ->
        # chunk events by stream
        events
        |> Enum.chunk_by(fn event -> event.stream_id end)
        |> Enum.map(fn events_by_stream ->
          last_event = List.last(events_by_stream)

          notify_subscriber(data, events_by_stream)
          ack_events(data, events_by_stream, last_event.event_id)

          last_event
        end)
        |> Enum.reduce(fn (last_event, _) -> last_event end)
    end

    data = %SubscriptionData{data |
      latest_event_id: latest_event_id,
      last_seen_event_id: last_event.event_id,
      last_seen_stream_version: last_event.stream_version
    }
  end

  defp unseen_events(%SubscriptionData{stream_uuid: @all_stream, last_seen_event_id: last_seen_event_id}) do
    start_event_id = last_seen_event_id + 1

    Storage.read_all_streams_forward(start_event_id)
  end

  defp unseen_events(%SubscriptionData{stream_uuid: stream_uuid, last_seen_stream_version: last_seen_stream_version}) do
    start_version = last_seen_stream_version + 1

    Storage.read_stream_forward(stream_uuid, start_version)
  end

  defp notify_subscriber(%SubscriptionData{subscriber: subscriber} = data, events) do
    send(subscriber, {:events, events})
  end

  defp ack_events(%SubscriptionData{stream_uuid: stream_uuid, subscription_name: subscription_name} = data, events, last_event_id) do
    Storage.ack_last_seen_event(stream_uuid, subscription_name, last_event_id)
  end
end
