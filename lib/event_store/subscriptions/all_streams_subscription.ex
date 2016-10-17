defmodule EventStore.Subscriptions.AllStreamsSubscription do
  require Logger

  defmodule SubscriptionData do
    defstruct subscription_name: nil,
              source: nil,
              subscriber: nil,
              last_seen_event_id: 0,
              last_ack_event_id: 0,
              pending_events: []
  end

  alias EventStore.Storage
  alias EventStore.Streams.AllStream

  use Fsm, initial_state: :initial, initial_data: %SubscriptionData{}

  @all_stream "$all"

  defstate initial do
    defevent subscribe(@all_stream, _stream, subscription_name, source, subscriber), data: %SubscriptionData{} = data do
      case subscribe_to_stream(subscription_name) do
        {:ok, subscription} ->
          data = %SubscriptionData{data |
            subscription_name: subscription_name,
            source: source,
            subscriber: subscriber,
            last_seen_event_id: (subscription.last_seen_event_id || 0),
            last_ack_event_id: (subscription.last_seen_event_id || 0),
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

    defevent ack(event_id), data: %SubscriptionData{} = data do
      ack_events(data, event_id)

      data = %SubscriptionData{data| last_ack_event_id: event_id}

      next_state(:catching_up, data)
    end

    # ignore event notifications while catching up
    defevent notify_events(_events), data: %SubscriptionData{} = data do
      next_state(:catching_up, data)
    end

    defevent unsubscribe, data: %SubscriptionData{subscription_name: subscription_name} = data do
      unsubscribe_from_stream(subscription_name)
      next_state(:unsubscribed, data)
    end
  end

  defstate subscribed do
    # notify events for all streams subscription
    defevent notify_events(events), data: %SubscriptionData{last_seen_event_id: last_seen_event_id, last_ack_event_id: last_ack_event_id, pending_events: pending_events} = data do
      expected_event_id = last_seen_event_id + 1
      next_ack_event_id = last_ack_event_id + 1

      case first_event_id(events) do
        ^next_ack_event_id ->
          # subscriber is up-to-date, so send events
          notify_subscriber(data, events)

          data = %SubscriptionData{data |
            last_seen_event_id: List.last(events).event_id
          }

          next_state(:subscribed, data)

        ^expected_event_id ->
          # subscriber has not yet ack'd last seen event so enqueue them until they are ready
          data = %SubscriptionData{data |
            last_seen_event_id: List.last(events).event_id,
            pending_events: pending_events ++ events
          }

          next_state(:subscribed, data)

        _ ->
          # must catch-up with all unseen events
          next_state(:catching_up, data)
      end
    end

    defevent ack(event_id), data: %SubscriptionData{pending_events: pending_events} = data do
      ack_events(data, event_id)

      notify_subscriber(data, pending_events)

      data = %SubscriptionData{data|
        pending_events: [],
        last_ack_event_id: event_id
      }

      next_state(:subscribed, data)
    end

    defevent catch_up, data: %SubscriptionData{} = data do
      next_state(:catching_up, data)
    end

    defevent unsubscribe, data: %SubscriptionData{subscription_name: subscription_name} = data do
      unsubscribe_from_stream(subscription_name)
      next_state(:unsubscribed, data)
    end
  end

  defstate unsubscribed do
    defevent notify_events(_events), data: %SubscriptionData{} = data do
      next_state(:unsubscribed, data)
    end
  end

  defstate failed do
    defevent notify_events(_events), data: %SubscriptionData{} = data do
      next_state(:failed, data)
    end
  end

  defp subscribe_to_stream(subscription_name) do
    Storage.subscribe_to_stream(@all_stream, subscription_name)
  end

  defp unsubscribe_from_stream(subscription_name) do
    Storage.unsubscribe_from_stream(@all_stream, subscription_name)
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

    AllStream.read_stream_forward(start_event_id)
  end

  defp notify_subscriber(%SubscriptionData{}, []) do
    # no-op
  end

  defp notify_subscriber(%SubscriptionData{subscriber: subscriber, source: source}, events) do
    send(subscriber, {:events, events, source})
  end

  defp ack_events(%SubscriptionData{subscription_name: subscription_name}, last_event_id) do
    Storage.ack_last_seen_event(@all_stream, subscription_name, last_event_id, nil)
  end

  defp first_event_id([first_event|_]) do
    first_event.event_id
  end
end
