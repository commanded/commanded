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
              pending_events: [],
              max_size: nil
  end

  alias EventStore.Storage
  alias EventStore.Subscriptions.{AllStreamsSubscription,SingleStreamSubscription}

  use Fsm, initial_state: :initial, initial_data: %SubscriptionData{}

  @all_stream "$all"
  @max_buffer_size 1_000

  defstate initial do
    defevent subscribe(stream_uuid, stream, subscription_name, source, subscriber, opts), data: %SubscriptionData{} = data do
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
            last_ack: last_ack,
            max_size: opts[:max_size] || @max_buffer_size
          }

          next_state(:catching_up, data)

        {:error, _reason} ->
          next_state(:failed, data)
      end
    end
  end

  defstate catching_up do
    defevent catch_up, data: %SubscriptionData{} = data do
      {state, data} = catch_up_from_stream(data)

      next_state(state, data)
    end

    defevent ack(ack), data: %SubscriptionData{} = data do
      data =
        data
        |> ack_events(ack)
        |> notify_pending_events

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
    defevent notify_events(events), data: %SubscriptionData{stream_uuid: stream_uuid, last_seen: last_seen, last_ack: last_ack, pending_events: pending_events, max_size: max_size} = data do
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
          # subscriber has not yet ack'd last seen event so enqueue them until they are ready
          data = %SubscriptionData{data |
            last_seen: subscription_provider(stream_uuid).event_id(List.last(events)),
            pending_events: pending_events ++ events
          }

          if length(pending_events) + length(events) >= max_size do
            # subscriber is too far behind, must wait for it to catch up
            next_state(:max_capacity, data)
          else
            next_state(:subscribed, data)
          end

        _ ->
          # must catch-up with all unseen events
          next_state(:catching_up, data)
      end
    end

    defevent ack(ack), data: %SubscriptionData{} = data do
      data =
        data
        |> ack_events(ack)
        |> notify_pending_events

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

  defstate max_capacity do
    # ignore event notifications while over capacity
    defevent notify_events(_events), data: %SubscriptionData{} = data do
      next_state(:max_capacity, data)
    end

    defevent ack(ack), data: %SubscriptionData{} = data do
      data =
        data
        |> ack_events(ack)
        |> notify_pending_events

      case data.pending_events do
        [] ->
          # no further pending events so catch up with any unseen
          next_state(:catching_up, data)

        _ ->
          # pending events remain, wait until subscriber ack's
          next_state(:max_capacity, data)
      end
    end

    defevent catch_up, data: %SubscriptionData{} = data do
      next_state(:max_capacity, data)
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

    defevent ack(_ack), data: %SubscriptionData{} = data do
      next_state(:unsubscribed, data)
    end

    defevent catch_up, data: %SubscriptionData{} = data do
      next_state(:unsubscribed, data)
    end

    defevent unsubscribe, data: %SubscriptionData{} = data do
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

  # fetch unseen events from the stream
  # transition to `subscribed` state when no events are found or count of events is less than max buffer size so no further unseen events
  defp catch_up_from_stream(%SubscriptionData{stream_uuid: stream_uuid, stream: stream, last_seen: last_seen} = data) do
    case subscription_provider(stream_uuid).unseen_events(stream, last_seen, @max_buffer_size) do
      {:ok, []} -> {:subscribed, data}
      {:ok, events} ->
        last_event = notify_subscriber_events(data, events)
        data = %SubscriptionData{data | last_seen: subscription_provider(stream_uuid).event_id(last_event)}

        if length(events) < @max_buffer_size do
          {:subscribed, data}
        else
          {:catching_up, data}
        end
    end
  end

  # chunk events by correlation id and send to subscriber
  # returns the last notified event
  defp notify_subscriber_events(%SubscriptionData{} = data, events) do
    events
    |> Enum.chunk_by(fn event -> event.correlation_id end)
    |> Enum.map(fn events_by_correlation_id ->
      notify_subscriber(data, events_by_correlation_id)

      List.last(events_by_correlation_id)
    end)
    |> Enum.reduce(fn (last_event, _) -> last_event end)
  end

  # send pending events to subscriber if ready to receive them
  defp notify_pending_events(%SubscriptionData{pending_events: []} = data), do: data
  defp notify_pending_events(%SubscriptionData{pending_events: [first_pending_event|_] = pending_events, stream_uuid: stream_uuid, last_ack: last_ack} = data) do
    next_ack = last_ack + 1

    case subscription_provider(stream_uuid).event_id(first_pending_event) do
      ^next_ack ->
        # subscriber has ack'd last received event, so send pending
        notify_subscriber_events(data, pending_events)

        %SubscriptionData{data|
          pending_events: []
        }

      _ ->
        # subscriber has not yet ack'd last received event, don't send any more
        data
    end
  end

  defp notify_subscriber(%SubscriptionData{}, []), do: nil
  defp notify_subscriber(%SubscriptionData{subscriber: subscriber, source: source}, events) do
    send(subscriber, {:events, events, source})
  end

  defp ack_events(%SubscriptionData{stream_uuid: stream_uuid, subscription_name: subscription_name} = data, ack) do
    :ok = subscription_provider(stream_uuid).ack_last_seen_event(stream_uuid, subscription_name, ack)

    %SubscriptionData{data| last_ack: ack}
  end
end
