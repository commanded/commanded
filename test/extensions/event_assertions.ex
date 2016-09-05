defmodule Commanded.Extensions.EventAssertions do
  use ExUnit.Case

  def assert_receive_event(event_type, assertion) do
    assert_receive_event(event_type, assertion, skip: 0)
  end

  def assert_receive_event(event_type, assertion, skip: skip) do
    subscription_name = UUID.uuid4

    create_subscription(subscription_name)

    try do
      do_assert_receive(event_type, assertion, skip: skip)
    after
      remove_subscription(subscription_name)
    end
  end

  defp create_subscription(subscription_name) do
    {:ok, _subscription} = EventStore.subscribe_to_all_streams(subscription_name, self)
  end

  defp remove_subscription(subscription_name) do
    EventStore.unsubscribe_from_all_streams(subscription_name)
  end

  defp do_assert_receive(event_type, assertion, skip: 0) do
    assert_receive {:events, received_events}, 1_000

    expected_type = Atom.to_string(event_type)
    expected_event = Enum.find(received_events, fn received_event ->
      case received_event.event_type do
        ^expected_type -> true
        _ -> false
      end
    end)

    case expected_event do
      nil -> do_assert_receive(event_type, assertion, skip: 0)
      received_event -> assertion.(received_event.data)
    end
  end

  defp do_assert_receive(event_type, assertion, skip: skip) do
    assert_receive {:events, _skip_event}, 1_000
    do_assert_receive(event_type, assertion, skip: skip - 1)
  end
end
