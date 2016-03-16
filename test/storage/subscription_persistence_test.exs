defmodule EventStore.Storage.SubscriptionPersistenceTest do
  use EventStore.StorageCase

  alias EventStore.Storage

  @all_stream "$all"
  @subscription_name "test_subscription"

  test "create subscription" do
    {:ok, subscription} = Storage.subscribe_to_stream(@all_stream, @subscription_name)

    verify_subscription(subscription)
  end

  test "create subscription when already exists" do
    {:ok, subscription1} = Storage.subscribe_to_stream(@all_stream, @subscription_name)
    {:ok, subscription2} = Storage.subscribe_to_stream(@all_stream, @subscription_name)

    verify_subscription(subscription1)
    verify_subscription(subscription2)

    assert subscription1.subscription_id == subscription2.subscription_id
  end

  test "list subscriptions" do
    {:ok, subscription} = Storage.subscribe_to_stream(@all_stream, @subscription_name)
    {:ok, subscriptions} = Storage.subscriptions

    assert length(subscriptions) > 0
    assert Enum.member?(subscriptions, subscription)
  end

  test "remove subscription when exists" do
    {:ok, subscriptions} = Storage.subscriptions
    initial_length = length(subscriptions)

    {:ok, _subscription} = Storage.subscribe_to_stream(@all_stream, @subscription_name)
    :ok = Storage.unsubscribe_from_stream(@all_stream, @subscription_name)

    {:ok, subscriptions} = Storage.subscriptions
    assert length(subscriptions) == initial_length
  end

  test "remove subscription when not found should not fail" do
    :ok = Storage.unsubscribe_from_stream(@all_stream, @subscription_name)
  end

  test "ack last seen event" do
    {:ok, _subscription} = Storage.subscribe_to_stream(@all_stream, @subscription_name)

    :ok = Storage.ack_last_seen_event(@all_stream, @subscription_name, 1)

    {:ok, subscriptions} = Storage.subscriptions

    subscription = subscriptions |> Enum.reverse |> hd

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
