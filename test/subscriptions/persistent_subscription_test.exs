defmodule EventStore.Subscription.PersistentSubscriptionTest do
  use EventStore.StorageCase
  doctest EventStore.Subscriptions.PersistentSubscription

  alias EventStore.{EventFactory,Storage,Subscriber}
  alias EventStore.Subscriptions.PersistentSubscription

  @all_stream "$all"
  @subscription_name "test_subscription"

  test "create subscription to stream", %{storage: storage} do
    stream_uuid = UUID.uuid4()
    {:ok, subscriber} = Subscriber.start_link(self)

    subscription = PersistentSubscription.new
    |> PersistentSubscription.subscribe(storage, stream_uuid, @subscription_name, subscriber)

    assert subscription.state == :catching_up
    assert subscription.data.stream_uuid == stream_uuid
    assert subscription.data.subscription_name == @subscription_name
    assert subscription.data.subscriber == subscriber
    assert subscription.data.last_seen_event_id == 0
    assert subscription.data.latest_event_id == 0
  end

  test "catch-up subscription, no persisted events", %{storage: storage} do
    stream_uuid = UUID.uuid4()
    {:ok, subscriber} = Subscriber.start_link(self)

    subscription = PersistentSubscription.new
    |> PersistentSubscription.subscribe(storage, stream_uuid, @subscription_name, subscriber)
    |> PersistentSubscription.catch_up

    assert subscription.state == :subscribed
    assert subscription.data.last_seen_event_id == 0
    assert subscription.data.latest_event_id == 0
  end

  test "catch-up subscription, unseen persisted events", %{storage: storage} do
    stream_uuid = UUID.uuid4()
    events = EventFactory.create_events(3)

    {:ok, subscriber} = Subscriber.start_link(self)
    {:ok, _} = Storage.append_to_stream(storage, stream_uuid, 0, events)

    subscription = PersistentSubscription.new
    |> PersistentSubscription.subscribe(storage, stream_uuid, @subscription_name, subscriber)
    |> PersistentSubscription.catch_up

    assert subscription.state == :subscribed
    assert subscription.data.last_seen_event_id == 3
    assert subscription.data.latest_event_id == 3

    assert_receive {:events, received_events}

    assert correlation_id(received_events) == correlation_id(events)
    assert payload(received_events) == payload(events)
  end

  test "notify events", %{storage: storage} do
    stream_uuid = UUID.uuid4()
    events = EventFactory.create_recorded_events(1, stream_uuid)
    {:ok, subscriber} = Subscriber.start_link(self)

    subscription = PersistentSubscription.new
    |> PersistentSubscription.subscribe(storage, stream_uuid, @subscription_name, subscriber)
    |> PersistentSubscription.catch_up
    |> PersistentSubscription.notify_events(events)

    assert subscription.state == :subscribed

    assert_receive {:events, received_events}

    assert correlation_id(received_events) == correlation_id(events)
    assert payload(received_events) == payload(events)
  end

  defp correlation_id(events), do: Enum.map(events, &(&1.correlation_id))
  defp payload(events), do: Enum.map(events, &(&1.payload))
end
