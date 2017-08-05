defmodule EventStore.Subscriptions.StreamSubscription do
  require Logger


  alias EventStore.Storage
  alias EventStore.Subscriptions.{
    AllStreamsSubscription,
    SingleStreamSubscription,
    SubscriptionState,
  }

  use Fsm, initial_state: :initial, initial_data: %SubscriptionState{}

  @all_stream "$all"
  @max_buffer_size 1_000

  defstate initial do
    defevent subscribe(stream_uuid, subscription_name, subscriber, opts), data: %SubscriptionState{} = data do
      case subscribe_to_stream(stream_uuid, subscription_name, opts[:start_from_event_id], opts[:start_from_stream_version]) do
        {:ok, subscription} ->
          last_ack = subscription_provider(stream_uuid).last_ack(subscription) || 0

          data = %SubscriptionState{data |
            stream_uuid: stream_uuid,
            subscription_name: subscription_name,
            subscriber: subscriber,
            mapper: opts[:mapper],
            last_seen: last_ack,
            last_ack: last_ack,
            max_size: opts[:max_size] || @max_buffer_size,
          }

          case last_ack do
            -1 -> next_state(:subscribed, data)
            _  -> next_state(:request_catch_up, data)
          end

        {:error, _reason} ->
          next_state(:failed, data)
      end
    end
  end

  defstate request_catch_up do
    defevent catch_up(notification_callback), data: %SubscriptionState{} = data do
      catch_up_from_stream(data, notification_callback)

      next_state(:catching_up, data)
    end

    defevent ack(ack), data: %SubscriptionState{} = data do
      data =
        data
        |> ack_events(ack)
        |> notify_pending_events()

      next_state(:request_catch_up, data)
    end

    # ignore event notifications while catching up
    defevent notify_events(_events), data: %SubscriptionState{} = data do
      next_state(:request_catch_up, data)
    end

    defevent unsubscribe, data: %SubscriptionState{stream_uuid: stream_uuid, subscription_name: subscription_name} = data do
      unsubscribe_from_stream(stream_uuid, subscription_name)
      next_state(:unsubscribed, data)
    end
  end

  defstate catching_up do
    defevent catch_up(_notification_callback), data: %SubscriptionState{} = data do
      next_state(:catching_up, data)
    end

    defevent ack(ack), data: %SubscriptionState{} = data do
      data =
        data
        |> ack_events(ack)
        |> notify_pending_events()

      next_state(:catching_up, data)
    end

    defevent caught_up(last_seen), data: %SubscriptionState{} = data do
      data = %SubscriptionState{data |
        last_seen: last_seen,
      }

      next_state(:subscribed, data)
    end

    # ignore event notifications while catching up
    defevent notify_events(_events), data: %SubscriptionState{} = data do
      next_state(:catching_up, data)
    end

    defevent unsubscribe, data: %SubscriptionState{stream_uuid: stream_uuid, subscription_name: subscription_name} = data do
      unsubscribe_from_stream(stream_uuid, subscription_name)
      next_state(:unsubscribed, data)
    end
  end

  defstate subscribed do
    # immediately notify events for new subscriptions from `:current`
    defevent notify_events(events), data: %SubscriptionState{stream_uuid: stream_uuid, last_seen: -1, last_ack: -1, pending_events: []} = data do
      notify_subscriber(data, events)

      next_state(:subscribed, data)
    end

    # notify events for single stream subscription
    defevent notify_events(events), data: %SubscriptionState{stream_uuid: stream_uuid, last_seen: last_seen, last_ack: last_ack, pending_events: pending_events, max_size: max_size} = data do
      expected_event = last_seen + 1
      next_ack = last_ack + 1

      case subscription_provider(stream_uuid).event_id(hd(events)) do
        ^next_ack ->
          # subscriber is up-to-date, so send events
          notify_subscriber(data, events)

          data = %SubscriptionState{data |
            last_seen: subscription_provider(stream_uuid).event_id(List.last(events))
          }

          next_state(:subscribed, data)

        ^expected_event ->
          # subscriber has not yet ack'd last seen event so enqueue them until they are ready
          data = %SubscriptionState{data |
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
          next_state(:request_catch_up, data)
      end
    end

    defevent ack(ack), data: %SubscriptionState{} = data do
      data =
        data
        |> ack_events(ack)
        |> notify_pending_events()

      next_state(:subscribed, data)
    end

    defevent catch_up(_notification_callback), data: %SubscriptionState{} = data do
      next_state(:request_catch_up, data)
    end

    defevent unsubscribe, data: %SubscriptionState{stream_uuid: stream_uuid, subscription_name: subscription_name} = data do
      unsubscribe_from_stream(stream_uuid, subscription_name)
      next_state(:unsubscribed, data)
    end
  end

  defstate max_capacity do
    # ignore event notifications while over capacity
    defevent notify_events(_events), data: %SubscriptionState{} = data do
      next_state(:max_capacity, data)
    end

    defevent ack(ack), data: %SubscriptionState{} = data do
      data =
        data
        |> ack_events(ack)
        |> notify_pending_events()

      case data.pending_events do
        [] ->
          # no further pending events so catch up with any unseen
          next_state(:request_catch_up, data)

        _ ->
          # pending events remain, wait until subscriber ack's
          next_state(:max_capacity, data)
      end
    end

    defevent catch_up(_notification_callback), data: %SubscriptionState{} = data do
      next_state(:max_capacity, data)
    end

    defevent unsubscribe, data: %SubscriptionState{stream_uuid: stream_uuid, subscription_name: subscription_name} = data do
      unsubscribe_from_stream(stream_uuid, subscription_name)
      next_state(:unsubscribed, data)
    end
  end

  defstate unsubscribed do
    defevent notify_events(_events), data: %SubscriptionState{} = data do
      next_state(:unsubscribed, data)
    end

    defevent ack(_ack), data: %SubscriptionState{} = data do
      next_state(:unsubscribed, data)
    end

    defevent catch_up(_notification_callback), data: %SubscriptionState{} = data do
      next_state(:unsubscribed, data)
    end

    defevent unsubscribe, data: %SubscriptionState{} = data do
      next_state(:unsubscribed, data)
    end
  end

  defstate failed do
    defevent notify_events(_events), data: %SubscriptionState{} = data do
      next_state(:failed, data)
    end
  end

  defp subscription_provider(@all_stream), do: AllStreamsSubscription
  defp subscription_provider(_stream_uuid), do: SingleStreamSubscription

  defp subscribe_to_stream(stream_uuid, subscription_name, start_from_event_id, start_from_stream_version) do
    Storage.subscribe_to_stream(stream_uuid, subscription_name, start_from_event_id, start_from_stream_version)
  end

  defp unsubscribe_from_stream(stream_uuid, subscription_name) do
    Storage.unsubscribe_from_stream(stream_uuid, subscription_name)
  end

  # fetch unseen events from the stream
  # transition to `subscribed` state when no events are found or count of events is less than max buffer size so no further unseen events
  defp catch_up_from_stream(%SubscriptionState{stream_uuid: stream_uuid, last_seen: last_seen} = data, notification_callback) do
    case subscription_provider(stream_uuid).unseen_event_stream(stream_uuid, last_seen, @max_buffer_size) do
      {:error, :stream_not_found} -> notification_callback.(last_seen)
      unseen_event_stream ->
        # stream through unseen events in a separate process
        spawn_link(fn ->
          last_event =
            unseen_event_stream
            |> Stream.chunk_by(&(&1.stream_id))
            |> Stream.each(&notify_subscriber(data, &1))
            |> Stream.map(&Enum.at(&1, -1))
            |> Enum.at(-1)

          last_seen = case last_event do
            nil -> last_seen
            event -> subscription_provider(stream_uuid).event_id(event)
          end

          # notify subscription caught up to given last seen event
          notification_callback.(last_seen)
        end)
    end
  end

  # send pending events to subscriber if ready to receive them
  defp notify_pending_events(%SubscriptionState{pending_events: []} = data), do: data
  defp notify_pending_events(%SubscriptionState{pending_events: [first_pending_event | _] = pending_events, stream_uuid: stream_uuid, last_ack: last_ack} = data) do
    next_ack = last_ack + 1

    case subscription_provider(stream_uuid).event_id(first_pending_event) do
      ^next_ack ->
        # subscriber has ack'd last received event, so send pending
        pending_events
        |> Enum.chunk_by(&(&1.stream_id))
        |> Enum.each(&notify_subscriber(data, &1))

        %SubscriptionState{data|
          pending_events: []
        }

      _ ->
        # subscriber has not yet ack'd last received event, don't send any more
        data
    end
  end

  defp notify_subscriber(%SubscriptionState{}, []), do: nil
  defp notify_subscriber(%SubscriptionState{subscriber: subscriber, mapper: mapper}, events) when is_function(mapper) do
    send_to_subscriber(subscriber, Enum.map(events, mapper))
  end
  defp notify_subscriber(%SubscriptionState{subscriber: subscriber}, events), do: send_to_subscriber(subscriber, events)

  defp send_to_subscriber(subscriber, events) do
    send(subscriber, {:events, events})
  end

  defp ack_events(%SubscriptionState{stream_uuid: stream_uuid, subscription_name: subscription_name} = data, ack) do
    :ok = subscription_provider(stream_uuid).ack_last_seen_event(stream_uuid, subscription_name, ack)

    %SubscriptionState{data| last_ack: ack}
  end
end
