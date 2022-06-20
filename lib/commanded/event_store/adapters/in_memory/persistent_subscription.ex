defmodule Commanded.EventStore.Adapters.InMemory.PersistentSubscription do
  @moduledoc false

  alias Commanded.EventStore.Adapters.InMemory.Subscriber
  alias Commanded.EventStore.RecordedEvent
  alias __MODULE__

  defstruct [
    :checkpoint,
    :concurrency_limit,
    :name,
    :partition_by,
    :ref,
    :start_from,
    :stream_uuid,
    subscribers: []
  ]

  @doc """
  Subscribe a new subscriber to the persistent subscription.
  """
  def subscribe(%PersistentSubscription{} = subscription, pid, checkpoint) do
    %PersistentSubscription{subscribers: subscribers} = subscription

    subscribers = subscribers ++ [Subscriber.new(pid)]

    %PersistentSubscription{subscription | subscribers: subscribers, checkpoint: checkpoint}
  end

  def has_subscriber?(%PersistentSubscription{} = subscription, pid) do
    %PersistentSubscription{subscribers: subscribers} = subscription

    Enum.any?(subscribers, fn
      %Subscriber{pid: ^pid} -> true
      %Subscriber{} -> false
    end)
  end

  @doc """
  Publish event to any available subscriber.
  """
  def publish(%PersistentSubscription{} = subscription, %RecordedEvent{} = event) do
    %PersistentSubscription{subscribers: subscribers} = subscription
    %RecordedEvent{event_number: event_number} = event

    if subscriber = subscriber(subscription, event) do
      subscribers =
        Enum.map(subscribers, fn
          ^subscriber -> Subscriber.publish(subscriber, event)
          %Subscriber{} = subscriber -> subscriber
        end)

      subscription = %PersistentSubscription{
        subscription
        | subscribers: subscribers,
          checkpoint: event_number
      }

      {:ok, subscription}
    else
      {:error, :no_subscriber_available}
    end
  end

  @doc """
  Acknowledge a successfully received event.
  """
  def ack(%PersistentSubscription{} = subscription, ack) do
    %PersistentSubscription{subscribers: subscribers} = subscription

    subscriber =
      Enum.find(subscribers, fn %Subscriber{in_flight_events: in_flight_events} ->
        Enum.any?(in_flight_events, fn %RecordedEvent{event_number: event_number} ->
          event_number == ack
        end)
      end)

    if subscriber do
      subscribers =
        Enum.map(subscribers, fn
          ^subscriber -> Subscriber.ack(subscriber, ack)
          subscriber -> subscriber
        end)

      %PersistentSubscription{subscription | subscribers: subscribers}
    else
      {:error, :unexpected_ack}
    end
  end

  @doc """
  Unsubscribe an existing subscriber from the persistent subscription.
  """
  def unsubscribe(%PersistentSubscription{} = subscription, pid) do
    %PersistentSubscription{checkpoint: checkpoint, subscribers: subscribers} = subscription

    subscriber =
      Enum.find(subscribers, fn
        %Subscriber{pid: ^pid} -> true
        %Subscriber{} -> false
      end)

    if subscriber do
      %Subscriber{in_flight_events: in_flight_events} = subscriber

      subscribers = List.delete(subscribers, subscriber)

      checkpoint =
        Enum.reduce(in_flight_events, checkpoint, fn %RecordedEvent{} = event, checkpoint ->
          %RecordedEvent{event_number: event_number} = event

          min(event_number - 1, checkpoint)
        end)

      %PersistentSubscription{subscription | checkpoint: checkpoint, subscribers: subscribers}
    else
      subscription
    end
  end

  # Get the subscriber to send the event to determined by the partition function
  # if provided, otherwise use a round-robin distribution strategy.
  defp subscriber(%PersistentSubscription{} = subscription, %RecordedEvent{} = event) do
    %PersistentSubscription{partition_by: partition_by, subscribers: subscribers} = subscription

    if is_function(partition_by, 1) do
      # Find subscriber by partition function
      partition_key = partition_by.(event)

      index = :erlang.phash2(partition_key, length(subscribers))

      Enum.at(subscribers, index)
    else
      # Find first available subscriber
      Enum.find(subscribers, &Subscriber.available?/1)
    end
  end
end
