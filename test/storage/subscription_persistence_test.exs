defmodule EventStore.Storage.SubsriptionPersistenceTest do
  use ExUnit.Case
  doctest EventStore.Storage

  alias EventStore.EventFactory
  alias EventStore.Storage

  setup do
    {:ok, store} = Storage.start_link
    {:ok, store: store}
  end

  @subscription_name "test_subscription"
  @all_stream "$all"

  test "create subscription", %{store: store} do
    {:ok, subscription} = Storage.subscribe_to_stream(store, @all_stream, @subscription_name)

    verify_subscription(subscription)
  end

  test "create subscription when already exists", %{store: store} do
    {:ok, subscription1} = Storage.subscribe_to_stream(store, @all_stream, @subscription_name)
    {:ok, subscription2} = Storage.subscribe_to_stream(store, @all_stream, @subscription_name)

    verify_subscription(subscription1)
    verify_subscription(subscription2)

    assert subscription1.subscription_id == subscription2.subscription_id
  end

  test "list subscriptions", %{store: store} do
    {:ok, subscription} = Storage.subscribe_to_stream(store, @all_stream, @subscription_name)

    {:ok, subscriptions} = Storage.subscriptions(store)

    assert length(subscriptions) == 1
    assert subscriptions == [subscription]
  end

  test "remove subscription when exists", %{store: store} do
    {:ok, subscription} = Storage.subscribe_to_stream(store, @all_stream, @subscription_name)
    :ok = Storage.unsubscribe_from_stream(store, @all_stream, @subscription_name)

    {:ok, subscriptions} = Storage.subscriptions(store)
    assert length(subscriptions) == 0
  end

  test "remove subscription when not found should not fail", %{store: store} do
    :ok = Storage.unsubscribe_from_stream(store, @all_stream, @subscription_name)
  end

  test "ack last seen event", %{store: store} do
    {:ok, subscription} = Storage.subscribe_to_stream(store, @all_stream, @subscription_name)
    
    :ok = Storage.ack_last_seen_event(store, @all_stream, @subscription_name, 1)

    {:ok, [subscriptions]} = Storage.subscriptions(store)

    verify_subscription(subscription, 1)
  end

  defp verify_subscription(subscription, last_seen_event_id \\ 0) do
    assert subscription.subscription_id > 0
    assert subscription.stream_uuid == @all_stream
    assert subscription.subscription_name == @subscription_name
    assert subscription.last_seen_event_id == last_seen_event_id
    assert subscription.created_at != nil
  end
end
