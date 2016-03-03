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

  @tag :wip
  test "create subscription", %{store: store} do

    {:ok, subscription} = Storage.subscribe_to_stream(store, @all_stream, @subscription_name)

    assert subscription.subscription_id > 0
    assert subscription.stream_uuid == @all_stream
    assert subscription.subscription_name == @subscription_name
    assert subscription.last_seen_event_id == 0
    assert subscription.created_at != nil
  end
end
