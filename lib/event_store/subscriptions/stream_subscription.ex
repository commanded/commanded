defmodule EventStore.Subscriptions.StreamSubscription do
  require Logger

  defmodule SubscriptionData do
    defstruct stream_uuid: nil,
              stream: nil,
              subscription_name: nil,
              source: nil,
              subscriber: nil,
              last_seen: 0,
              last_ack: 0,
              pending_events: []
  end

  alias EventStore.Storage
  alias EventStore.Subscriptions.{AllStreamsSubscription,SingleStreamSubscription}

  use Fsm, initial_state: :initial, initial_data: %SubscriptionData{}

  @all_stream "$all"

  defstate initial do
    defevent subscribe(stream_uuid, stream, subscription_name, source, subscriber), data: %SubscriptionData{} = data do
      case subscribe_to_stream(stream_uuid, subscription_name) do
        {:ok, subscription} ->
          last_ack = subscription_provider(stream_uuid).last_ack(subscription) || 0

          data = %SubscriptionData{data |
            stream_uuid: stream_uuid,
            stream: stream,
            subscription_name: subscription_name,
            source: source,
            subscriber: subscriber,
            last_seen: last_ack,
            last_ack: last_ack
          }
          next_state(:catching_up, data)

        {:error, _reason} ->
          next_state(:failed, data)
      end
    end
  end

  defstate catching_up do
    defevent catch_up, data: %SubscriptionData{stream_uuid: stream_uuid, stream: stream, last_seen: last_seen} = data do
      case subscription_provider(stream_uuid).state(stream) do
        {:ok, 0} ->
          # no events
          next_state(:subscribed, data)

        {:ok, ^last_seen} ->
          # already seen latest stream version
          next_state(:subscribed, data)

        {:ok, _last_seen} ->
          # must catch-up with all unseen events from stream
          data = catch_up_from_stream(data)

          next_state(:subscribed, data)
      end
    end

    defevent ack(ack), data: %SubscriptionData{} = data do
      ack_events(data, ack)

      data = %SubscriptionData{data| last_ack: ack}

      next_state(:catching_up, data)
    end

    # ignore event notifications while catching up
    defevent notify_events(_events), data: %SubscriptionData{} = data do
      next_state(:catching_up, data)
    end

    defevent unsubscribe, data: %SubscriptionData{stream_uuid: stream_uuid, subscription_name: subscription_name} = data do
      unsubscribe_from_stream(stream_uuid, subscription_name)
      next_state(:unsubscribed, data)
    end
  end

  defstate subscribed do
    # notify events for single stream subscription
    defevent notify_events(events), data: %SubscriptionData{stream_uuid: stream_uuid, last_seen: last_seen, last_ack: last_ack, pending_events: pending_events} = data do
      expected_event = last_seen + 1
      next_ack = last_ack + 1

      case subscription_provider(stream_uuid).event_id(hd(events)) do
        ^next_ack ->
          # subscriber is up-to-date, so send events
          notify_subscriber(data, events)

          data = %SubscriptionData{data |
            last_seen: subscription_provider(stream_uuid).event_id(List.last(events))
          }

          next_state(:subscribed, data)

        ^expected_event ->
          # subscriber has not yet ack'd last seen stream version so enqueue them until they are ready
          data = %SubscriptionData{data |
            last_seen: subscription_provider(stream_uuid).event_id(List.last(events)),
            pending_events: pending_events ++ events
          }

          next_state(:subscribed, data)

        _ ->
          # must catch-up with all unseen events
          next_state(:catching_up, data)
      end
    end

    defevent ack(ack), data: %SubscriptionData{pending_events: pending_events} = data do
      ack_events(data, ack)

      notify_subscriber(data, pending_events)

      data = %SubscriptionData{data|
        pending_events: [],
        last_ack: ack
      }

      next_state(:subscribed, data)
    end

    defevent catch_up, data: %SubscriptionData{} = data do
      next_state(:catching_up, data)
    end

    defevent unsubscribe, data: %SubscriptionData{stream_uuid: stream_uuid, subscription_name: subscription_name} = data do
      unsubscribe_from_stream(stream_uuid, subscription_name)
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

  defp subscription_provider(@all_stream), do: AllStreamsSubscription
  defp subscription_provider(_stream_uuid), do: SingleStreamSubscription

  defp subscribe_to_stream(stream_uuid, subscription_name) do
    Storage.subscribe_to_stream(stream_uuid, subscription_name)
  end

  defp unsubscribe_from_stream(stream_uuid, subscription_name) do
    Storage.unsubscribe_from_stream(stream_uuid, subscription_name)
  end

  defp catch_up_from_stream(%SubscriptionData{stream_uuid: stream_uuid, stream: stream, last_seen: last_seen} = data) do
    last_event = case subscription_provider(stream_uuid).unseen_events(stream, last_seen) do
      {:ok, events} ->
        # chunk events by correlation id
        events
        |> Enum.chunk_by(fn event -> event.correlation_id end)
        |> Enum.map(fn events_by_correlation_id ->
          last_event = List.last(events_by_correlation_id)

          notify_subscriber(data, events_by_correlation_id)

          last_event
        end)
        |> Enum.reduce(fn (last_event, _) -> last_event end)
    end

    %SubscriptionData{data | last_seen: subscription_provider(stream_uuid).event_id(last_event)}
  end

  defp notify_subscriber(%SubscriptionData{}, []) do
    # no-op
  end

  defp notify_subscriber(%SubscriptionData{subscriber: subscriber, source: source}, events) do
    send(subscriber, {:events, events, source})
  end

  defp ack_events(%SubscriptionData{stream_uuid: stream_uuid, subscription_name: subscription_name}, ack) do
    subscription_provider(stream_uuid).ack_last_seen_event(stream_uuid, subscription_name, ack)
  end
end
