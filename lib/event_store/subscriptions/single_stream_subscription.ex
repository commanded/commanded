defmodule EventStore.Subscriptions.SingleStreamSubscription do
  require Logger

  defmodule SubscriptionData do
    defstruct stream_uuid: nil,
              stream: nil,
              subscription_name: nil,
              source: nil,
              subscriber: nil,
              last_seen_stream_version: 0,
              last_ack_stream_version: 0,
              pending_events: []
  end

  alias EventStore.Storage
  alias EventStore.Streams.Stream

  use Fsm, initial_state: :initial, initial_data: %SubscriptionData{}

  defstate initial do
    defevent subscribe(stream_uuid, stream, subscription_name, source, subscriber), data: %SubscriptionData{} = data do
      case subscribe_to_stream(stream_uuid, subscription_name) do
        {:ok, subscription} ->
          data = %SubscriptionData{data |
            stream_uuid: stream_uuid,
            stream: stream,
            subscription_name: subscription_name,
            source: source,
            subscriber: subscriber,
            last_seen_stream_version: (subscription.last_seen_stream_version || 0),
            last_ack_stream_version: (subscription.last_seen_stream_version || 0)
          }
          next_state(:catching_up, data)
        {:error, _reason} ->
          next_state(:failed, data)
      end
    end
  end

  defstate catching_up do
    defevent catch_up, data: %SubscriptionData{stream: stream, last_seen_stream_version: last_seen_stream_version} = data do
      case Stream.stream_version(stream) do
        {:ok, 0} ->
          # no events
          next_state(:subscribed, data)

        {:ok, ^last_seen_stream_version} ->
          # already seen latest stream version
          next_state(:subscribed, data)

        {:ok, _latest_stream_version} ->
          # must catch-up with all unseen events from stream
          data = catch_up_to_stream_version(data)

          next_state(:subscribed, data)
      end
    end

    defevent ack(stream_version), data: %SubscriptionData{} = data do
      ack_events(data, stream_version)

      data = %SubscriptionData{data| last_ack_stream_version: stream_version}

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
    defevent notify_events(events), data: %SubscriptionData{last_seen_stream_version: last_seen_stream_version, last_ack_stream_version: last_ack_stream_version, pending_events: pending_events} = data do
      expected_stream_version = last_seen_stream_version + 1
      next_ack_stream_version = last_ack_stream_version + 1

      case first_stream_version(events) do
        ^next_ack_stream_version ->
          # subscriber is up-to-date, so send events
          notify_subscriber(data, events)

          data = %SubscriptionData{data |
            last_seen_stream_version: List.last(events).stream_version
          }

          next_state(:subscribed, data)

        ^expected_stream_version ->
          # subscriber has not yet ack'd last seen stream version so enqueue them until they are ready
          data = %SubscriptionData{data |
            last_seen_stream_version: List.last(events).stream_version,
            pending_events: pending_events ++ events
          }

          next_state(:subscribed, data)

        _ ->
          # must catch-up with all unseen events
          next_state(:catching_up, data)
      end
    end

    defevent ack(stream_version), data: %SubscriptionData{pending_events: pending_events} = data do
      ack_events(data, stream_version)

      notify_subscriber(data, pending_events)

      data = %SubscriptionData{data|
        pending_events: [],
        last_ack_stream_version: stream_version
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

  defp subscribe_to_stream(stream_uuid, subscription_name) do
    Storage.subscribe_to_stream(stream_uuid, subscription_name)
  end

  defp unsubscribe_from_stream(stream_uuid, subscription_name) do
    Storage.unsubscribe_from_stream(stream_uuid, subscription_name)
  end

  defp catch_up_to_stream_version(%SubscriptionData{stream: stream, last_seen_stream_version: last_seen_stream_version} = data) do
    last_event = case unseen_events(stream, last_seen_stream_version) do
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

    %SubscriptionData{data | last_seen_stream_version: last_event.stream_version}
  end

  defp unseen_events(stream, last_seen_stream_version) do
    start_version = last_seen_stream_version + 1

    Stream.read_stream_forward(stream, start_version)
  end

  defp notify_subscriber(%SubscriptionData{}, []) do
    # no-op
  end
  
  defp notify_subscriber(%SubscriptionData{subscriber: subscriber, source: source}, events) do
    send(subscriber, {:events, events, source})
  end

  defp ack_events(%SubscriptionData{stream_uuid: stream_uuid, subscription_name: subscription_name}, last_stream_version) do
    Storage.ack_last_seen_event(stream_uuid, subscription_name, nil, last_stream_version)
  end

  defp first_stream_version([first_event|_]), do: first_event.stream_version
end
