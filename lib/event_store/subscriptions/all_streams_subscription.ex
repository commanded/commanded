defmodule EventStore.Subscriptions.AllStreamsSubscription do
  require Logger

  defmodule SubscriptionData do
    defstruct subscription_name: nil,
              subscriber: nil,
              last_seen_event_id: 0
  end

  alias EventStore.Storage

  use Fsm, initial_state: :initial, initial_data: %SubscriptionData{}

  @all_stream "$all"

  defstate initial do
    defevent subscribe(@all_stream, _stream, subscription_name, subscriber), data: %SubscriptionData{} = data do
      case subscribe_to_stream(subscription_name) do
        {:ok, subscription} ->
          data = %SubscriptionData{data |
            subscription_name: subscription_name,
            subscriber: subscriber,
            last_seen_event_id: (subscription.last_seen_event_id || 0)
          }
          next_state(:catching_up, data)
        {:error, _reason} ->
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

        _latest_event_id ->
          # must catch-up with all unseen events
          data = catch_up_to_event(data)
          next_state(:subscribed, data)
      end
    end

    # ignore event notifications while catching up
    defevent notify_events(_events), data: %SubscriptionData{} = data do
      next_state(:catching_up, data)
    end
  end

  defstate subscribed do
    # notify events for all streams subscription
    defevent notify_events(events), data: %SubscriptionData{last_seen_event_id: last_seen_event_id} = data do
      expected_event_id = last_seen_event_id + 1

      case first_event_id(events) do
        ^expected_event_id ->
          last_event = List.last(events)

          notify_subscriber(data, events)
          ack_events(data, events, last_event.event_id)

          data = %SubscriptionData{data |
            last_seen_event_id: last_event.event_id
          }

          next_state(:subscribed, data)
        _ ->
          # must catch-up with all unseen events
          next_state(:catching_up, data)
      end
    end

    defevent catch_up, data: %SubscriptionData{} = data do
      next_state(:catching_up, data)
    end

    defevent unsubscribe, data: %SubscriptionData{} = data do
      next_state(:unsubscribed, data)
    end
  end

  defstate unsubscribed do
  end

  defstate failed do
  end

  defp subscribe_to_stream(subscription_name) do
    Storage.subscribe_to_stream(@all_stream, subscription_name)
  end

  defp query_latest_event_id do
    {:ok, latest_event_id} = Storage.latest_event_id
    latest_event_id
  end

  defp catch_up_to_event(%SubscriptionData{last_seen_event_id: last_seen_event_id} = data) do
    last_event = case unseen_events(last_seen_event_id) do
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

    %SubscriptionData{data |
      last_seen_event_id: last_event.event_id
    }
  end

  defp unseen_events(last_seen_event_id) do
    start_event_id = last_seen_event_id + 1

    Storage.read_all_streams_forward(start_event_id)
  end

  defp notify_subscriber(%SubscriptionData{subscriber: subscriber}, events) do
    send(subscriber, {:events, events})
  end

  defp ack_events(%SubscriptionData{subscription_name: subscription_name}, _events, last_event_id) do
    Storage.ack_last_seen_event(@all_stream, subscription_name, last_event_id, nil)
  end

  defp first_event_id([first_event|_]) do
    first_event.event_id
  end
end
