defmodule Commanded.Assertions.EventAssertions do
  @moduledoc """
  Provides test assertion and wait for event functions to help test applications built using Commanded.

  The default receive timeout is one second.

  You can override the default timeout in config (e.g. `config/test.exs`):

      config :commanded,
        assert_receive_event_timeout: 1_000

  """

  import ExUnit.Assertions

  alias Commanded.EventStore
  alias Commanded.EventStore.TypeProvider

  @doc """
  Wait for an event of the given event type to be published

  ## Examples

      wait_for_event BankAccountOpened

  """
  def wait_for_event(event_type) do
    wait_for_event(event_type, fn _event -> true end)
  end

  @doc """
  Wait for an event of the given event type, matching the predicate, to be published.

  ## Examples

      wait_for_event BankAccountOpened, fn opened -> opened.account_number == "ACC123" end

  """
  def wait_for_event(event_type, predicate_fn) when is_function(predicate_fn) do
    with_subscription(fn subscription ->
      do_wait_for_event(subscription, event_type, predicate_fn)
    end)
  end

  @doc """
  Assert that events matching their respective predicates have a matching correlation id.
  Useful when there is a chain of events that is connected through event handlers.

  ## Examples

      id_one = 1
      id_two = 2
      assert_correlated(
        BankAccountOpened, fn opened -> opened.id == id_one end,
        InitialAmountDeposited, fn deposited -> deposited.id == id_two end
      )
  """
  def assert_correlated(event_type_a, predicate_a, event_type_b, predicate_b) do
    assert_receive_event(event_type_a, predicate_a, fn _event_a, metadata_a ->
      assert_receive_event(event_type_b, predicate_b, fn _event_b, metadata_b ->
        assert metadata_a.correlation_id == metadata_b.correlation_id
      end)
    end)
  end

  @doc """
  Assert that an event of the given event type is published. Verify that event using the assertion function.

  ## Examples

      assert_receive_event BankAccountOpened, fn opened ->
        assert opened.account_number == "ACC123"
      end

  """
  def assert_receive_event(event_type, assertion_fn) do
    assert_receive_event(event_type, fn _event -> true end, assertion_fn)
  end

  @doc """
  Assert that an event of the given event type, matching the predicate, is published.
  Verify that event using the assertion function.

  ## Examples

      assert_receive_event BankAccountOpened,
        fn opened -> opened.account_number == "ACC123" end,
        fn opened ->
          assert opened.balance == 1_000
        end

  """
  def assert_receive_event(event_type, predicate_fn, assertion_fn) do
    unless Code.ensure_compiled?(event_type) do
      raise ExUnit.AssertionError, "event_type #{inspect(event_type)} not found"
    end

    with_subscription(fn subscription ->
      do_assert_receive(subscription, event_type, predicate_fn, assertion_fn)
    end)
  end

  defp default_receive_timeout,
    do: Application.get_env(:commanded, :assert_receive_event_timeout, 1_000)

  defp with_subscription(callback_fn) do
    subscription_name = UUID.uuid4()

    {:ok, subscription} = create_subscription(subscription_name)

    assert_receive {:subscribed, ^subscription}, default_receive_timeout()

    try do
      apply(callback_fn, [subscription])
    after
      remove_subscription(subscription_name)
    end
  end

  defp do_assert_receive(subscription, event_type, predicate_fn, assertion_fn) do
    assert_receive {:events, received_events}, default_receive_timeout()

    ack_events(subscription, received_events)

    expected_type = TypeProvider.to_string(event_type.__struct__)

    expected_event =
      Enum.find(received_events, fn received_event ->
        case received_event.event_type do
          ^expected_type ->
            case apply(predicate_fn, [received_event.data]) do
              true -> received_event
              _ -> false
            end

          _ ->
            false
        end
      end)

    case expected_event do
      nil ->
        do_assert_receive(subscription, event_type, predicate_fn, assertion_fn)

      received_event ->
        if is_function(assertion_fn, 1) do
          apply(assertion_fn, [received_event.data])
        else
          {data, all_metadata} = Map.split(received_event, [:data])
          apply(assertion_fn, [data, all_metadata])
        end
    end
  end

  defp do_wait_for_event(subscription, event_type, predicate_fn) do
    assert_receive {:events, received_events}, default_receive_timeout()

    ack_events(subscription, received_events)

    expected_type = TypeProvider.to_string(event_type.__struct__)

    expected_event =
      Enum.find(received_events, fn received_event ->
        case received_event.event_type do
          ^expected_type -> apply(predicate_fn, [received_event.data])
          _ -> false
        end
      end)

    case expected_event do
      nil -> do_wait_for_event(subscription, event_type, predicate_fn)
      received_event -> received_event
    end
  end

  defp create_subscription(subscription_name),
    do: EventStore.subscribe_to_all_streams(subscription_name, self(), :origin)

  defp remove_subscription(subscription_name),
    do: EventStore.unsubscribe_from_all_streams(subscription_name)

  defp ack_events(subscription, events), do: EventStore.ack_event(subscription, List.last(events))
end
