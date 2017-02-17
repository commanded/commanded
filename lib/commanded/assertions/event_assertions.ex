defmodule Commanded.Assertions.EventAssertions do
  import ExUnit.Assertions

  use Commanded.EventStore
  
  @default_receive_timeout 1_000

  @doc """
  Wait for an event of the given event type to be published
  """
  def wait_for_event(event_type) do
    wait_for_event(event_type, fn _event -> true end, @default_receive_timeout)
  end

  @doc """
  Wait for an event of the given event type to be published until the timeout.
  """
  def wait_for_event(event_type, timeout) when is_integer(timeout) do
    wait_for_event(event_type, fn _event -> true end, timeout)
  end

  @doc """
  Wait for an event of the given event type, matching the predicate, to be published.
  """
  def wait_for_event(event_type, predicate_fn) when is_function(predicate_fn) do
    wait_for_event(event_type, predicate_fn, @default_receive_timeout)
  end

  @doc """
  Wait for an event of the given event type, matching the predicate, to be published until the timeout.
  """
  def wait_for_event(event_type, predicate_fn, timeout) when is_function(predicate_fn) and is_integer(timeout) do
    with_subscription(fn ->
      do_wait_for_event(event_type, predicate_fn, timeout)
    end)
  end

  @doc """
  Assert that an event of the given event type is published. Verify that event using the assertion function.
  """
  def assert_receive_event(event_type, assertion_fn) do
    assert_receive_event(event_type, fn _event -> true end, assertion_fn)
  end

  @doc """
  Assert that an event of the given event type, matching the predicate, is published. Verify that event using the assertion function.
  """
  def assert_receive_event(event_type, predicate_fn, assertion_fn) do
    with_subscription(fn ->
      do_assert_receive(event_type, predicate_fn, assertion_fn)
    end)
  end

  defp with_subscription(callback_fn) do
    subscription_name = UUID.uuid4

    create_subscription(subscription_name)

    try do
      apply(callback_fn, [])
    after
      remove_subscription(subscription_name)
    end
  end

  defp create_subscription(subscription_name) do
    {:ok, _subscription} = @event_store.subscribe_to_all_streams(subscription_name, self())
  end

  defp remove_subscription(subscription_name) do
    @event_store.unsubscribe_from_all_streams(subscription_name)
  end

  defp do_assert_receive(event_type, predicate_fn, assertion_fn) do
    assert_receive {:events, received_events, subscription}, @default_receive_timeout

    ack_events(subscription, received_events)

    expected_type = Atom.to_string(event_type)
    expected_event = Enum.find(received_events, fn received_event ->
      case received_event.event_type do
        ^expected_type ->
          case apply(predicate_fn, [received_event.data]) do
            true -> received_event
            _ -> false
          end
        _ -> false
      end
    end)

    case expected_event do
      nil -> do_assert_receive(event_type, predicate_fn, assertion_fn)
      received_event -> apply(assertion_fn, [received_event.data])
    end
  end

  defp do_wait_for_event(event_type, predicate_fn, timeout) do
    assert_receive {:events, received_events, subscription}, timeout

    ack_events(subscription, received_events)

    expected_type = Atom.to_string(event_type)
    expected_event = Enum.find(received_events, fn received_event ->
      case received_event.event_type do
        ^expected_type -> apply(predicate_fn, [received_event.data])
        _ -> false
      end
    end)

    case expected_event do
      nil -> do_wait_for_event(event_type, predicate_fn, timeout)
      received_event -> received_event
    end
  end

  defp ack_events(subscription, events) do
    @event_store.ack_event(subscription, List.last(events))
  end
end
