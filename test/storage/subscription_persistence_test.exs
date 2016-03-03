defmodule EventStore.Storage.SubscriptionPersistenceTest do
  use ExUnit.Case
  doctest EventStore.Storage

  alias EventStore.EventFactory
  alias EventStore.Storage

  @all_stream "$all"

  setup do
    {:ok, store} = Storage.start_link
    {:ok, store: store}
  end

  test "create subscription", %{store: store} do
    subscription_name = UUID.uuid4()

    {:ok, subscription} = Storage.subscribe_to_stream(store, @all_stream, subscription_name)

    verify_subscription(subscription, subscription_name)
  end

  test "create subscription when already exists", %{store: store} do
    subscription_name = UUID.uuid4()

    {:ok, subscription1} = Storage.subscribe_to_stream(store, @all_stream, subscription_name)
    {:ok, subscription2} = Storage.subscribe_to_stream(store, @all_stream, subscription_name)

    verify_subscription(subscription1, subscription_name)
    verify_subscription(subscription2, subscription_name)

    assert subscription1.subscription_id == subscription2.subscription_id
  end

  test "list subscriptions", %{store: store} do
    subscription_name = UUID.uuid4()

    {:ok, subscription} = Storage.subscribe_to_stream(store, @all_stream, subscription_name)
    {:ok, subscriptions} = Storage.subscriptions(store)

    assert length(subscriptions) > 0
    assert Enum.member?(subscriptions, subscription)
  end

  test "remove subscription when exists", %{store: store} do
    subscription_name = UUID.uuid4()
    
    {:ok, subscriptions} = Storage.subscriptions(store)
    initial_length =length(subscriptions)

    {:ok, subscription} = Storage.subscribe_to_stream(store, @all_stream, subscription_name)
    :ok = Storage.unsubscribe_from_stream(store, @all_stream, subscription_name)

    {:ok, subscriptions} = Storage.subscriptions(store)
    assert length(subscriptions) == initial_length
  end

  test "remove subscription when not found should not fail", %{store: store} do
    subscription_name = UUID.uuid4()

    :ok = Storage.unsubscribe_from_stream(store, @all_stream, subscription_name)
  end

  test "ack last seen event", %{store: store} do
    subscription_name = UUID.uuid4()

    {:ok, subscription} = Storage.subscribe_to_stream(store, @all_stream, subscription_name)
    
    :ok = Storage.ack_last_seen_event(store, @all_stream, subscription_name, 1)

    {:ok, subscriptions} = Storage.subscriptions(store)

    subscription = subscriptions |> Enum.reverse |> hd

    verify_subscription(subscription, subscription_name, 1)
  end

  defp verify_subscription(subscription, subscription_name, last_seen_event_id \\ 0) do
    assert subscription.subscription_id > 0
    assert subscription.stream_uuid == @all_stream
    assert subscription.subscription_name == subscription_name
    assert subscription.last_seen_event_id == last_seen_event_id
    assert subscription.created_at != nil
  end
end
