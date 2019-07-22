defmodule Commanded.Assertions.EventAssertions do
  @moduledoc """
  Provides test assertion and wait for event functions to help test applications
  built using Commanded.

  The default assert and refute receive timeouts are one second.

  You can override the default timeout in config (e.g. `config/test.exs`):

      config :commanded,
        assert_receive_event_timeout: 1_000,
        refute_receive_event_timeout: 1_000

  """

  import ExUnit.Assertions

  alias Commanded.EventStore
  alias Commanded.EventStore.RecordedEvent

  @doc """
  Assert that events matching their respective predicates have a matching
  correlation id.

  Useful when there is a chain of events that is connected through event handlers.

  ## Example

      assert_correlated(
        BankApp,
        BankAccountOpened, fn opened -> opened.id == 1 end,
        InitialAmountDeposited, fn deposited -> deposited.id == 2 end
      )

  """
  def assert_correlated(application, event_type_a, predicate_a, event_type_b, predicate_b) do
    assert_receive_event(application, event_type_a, predicate_a, fn _event_a, metadata_a ->
      assert_receive_event(application, event_type_b, predicate_b, fn _event_b, metadata_b ->
        assert metadata_a.correlation_id == metadata_b.correlation_id
      end)
    end)
  end

  @doc """
  Assert that an event of the given event type is published.
  Verify that event using the assertion function.

  ## Example

      assert_receive_event(BankApp, BankAccountOpened, fn opened ->
        assert opened.account_number == "ACC123"
      end)

  """
  def assert_receive_event(application, event_type, assertion_fn) do
    assert_receive_event(application, event_type, fn _event -> true end, assertion_fn)
  end

  @doc """
  Assert that an event of the given event type, matching the predicate, is
  published. Verify that event using the assertion function.

  ## Example

      assert_receive_event(BankApp, BankAccountOpened,
        fn opened -> opened.account_number == "ACC123" end,
        fn opened ->
          assert opened.balance == 1_000
        end)

  """
  def assert_receive_event(application, event_type, predicate_fn, assertion_fn) do
    unless Code.ensure_compiled?(event_type) do
      raise ExUnit.AssertionError, "Event #{inspect(event_type)} not found"
    end

    with_subscription(application, fn subscription ->
      do_assert_receive(application, subscription, event_type, predicate_fn, assertion_fn)
    end)
  end

  @doc """
  Refute that an event of the given type has been received.

  An optional predicate may be provided to filter events matching the refuted
  type.

  ## Examples

  Refute that `ExampleEvent` is created by `some_func/0` function:

      refute_receive_event(ExampleApp, ExampleEvent) do
        some_func()
      end

  Refute that `ExampleEvent` matching given predicate is created by
  `some_func/0` function:

      refute_receive_event(ExampleApp, ExampleEvent,
        predicate: fn event -> event.foo == :foo end) do
        some_func()
      end

  """
  defmacro refute_receive_event(application, event_type, opts \\ [], do: block) do
    predicate = Keyword.get(opts, :predicate)
    timeout = Keyword.get(opts, :timeout, default_refute_receive_timeout())

    quote do
      task =
        Task.async(fn ->
          with_subscription(unquote(application), fn subscription ->
            predicate = unquote(predicate) || fn _event -> true end

            do_refute_receive_event(
              unquote(application),
              subscription,
              unquote(event_type),
              predicate
            )
          end)
        end)

      unquote(block)

      case Task.yield(task, unquote(timeout)) || Task.shutdown(task) do
        {:ok, :ok} -> :ok
        {:ok, {:error, event}} -> flunk("Unexpectedly received event: " <> inspect(event))
        {:error, error} -> flunk("Encountered an error: " <> inspect(error))
        {:exit, error} -> flunk("Encountered an error: " <> inspect(error))
        nil -> :ok
      end
    end
  end

  @doc """
  Wait for an event of the given event type to be published.

  ## Examples

      wait_for_event(BankApp, BankAccountOpened)

  """
  def wait_for_event(application, event_type) do
    wait_for_event(application, event_type, fn _event -> true end)
  end

  @doc """
  Wait for an event of the given event type, matching the predicate, to be
  published.

  ## Examples

      wait_for_event(BankApp, BankAccountOpened, fn opened ->
        opened.account_number == "ACC123"
      end)

  """
  def wait_for_event(application, event_type, predicate_fn) when is_function(predicate_fn) do
    with_subscription(application, fn subscription ->
      do_wait_for_event(application, subscription, event_type, predicate_fn)
    end)
  end

  @doc false
  def with_subscription(application, callback_fun) when is_function(callback_fun, 1) do
    subscription_name = UUID.uuid4()

    {:ok, subscription} =
      EventStore.subscribe_to(application, :all, subscription_name, self(), :origin)

    assert_receive {:subscribed, ^subscription}, default_receive_timeout()

    try do
      apply(callback_fun, [subscription])
    after
      :ok = EventStore.unsubscribe(application, subscription)
      :ok = EventStore.delete_subscription(application, :all, subscription_name)
    end
  end

  defp do_assert_receive(application, subscription, event_type, predicate_fn, assertion_fn) do
    assert_receive {:events, received_events}, default_receive_timeout()

    case find_expected_event(received_events, event_type, predicate_fn) do
      %RecordedEvent{data: data} = expected_event ->
        case assertion_fn do
          assertion_fn when is_function(assertion_fn, 1) ->
            apply(assertion_fn, [data])

          assertion_fn when is_function(assertion_fn, 2) ->
            apply(assertion_fn, [data, expected_event])
        end

      nil ->
        :ok = ack_events(application, subscription, received_events)

        do_assert_receive(application, subscription, event_type, predicate_fn, assertion_fn)
    end
  end

  def do_refute_receive_event(application, subscription, event_type, predicate_fn) do
    receive do
      {:events, events} ->
        case find_expected_event(events, event_type, predicate_fn) do
          %RecordedEvent{data: data} ->
            {:error, data}

          nil ->
            :ok = ack_events(application, subscription, events)

            do_refute_receive_event(application, subscription, event_type, predicate_fn)
        end
    end
  end

  defp do_wait_for_event(application, subscription, event_type, predicate_fn) do
    assert_receive {:events, received_events}, default_receive_timeout()

    case find_expected_event(received_events, event_type, predicate_fn) do
      %RecordedEvent{} = expected_event ->
        expected_event

      nil ->
        :ok = ack_events(application, subscription, received_events)

        do_wait_for_event(application, subscription, event_type, predicate_fn)
    end
  end

  defp find_expected_event(received_events, event_type, predicate_fn) do
    Enum.find(received_events, fn
      %RecordedEvent{data: %{__struct__: ^event_type} = data}
      when is_function(predicate_fn, 1) ->
        apply(predicate_fn, [data])

      %RecordedEvent{data: %{__struct__: ^event_type} = data} = received_event
      when is_function(predicate_fn, 2) ->
        apply(predicate_fn, [data, received_event])

      %RecordedEvent{} ->
        false
    end)
  end

  defp ack_events(_application, _subscription, []), do: :ok

  defp ack_events(application, subscription, [event]),
    do: EventStore.ack_event(application, subscription, event)

  defp ack_events(application, subscription, [_event | events]),
    do: ack_events(application, subscription, events)

  defp default_receive_timeout,
    do: Application.get_env(:commanded, :assert_receive_event_timeout, 1_000)

  defp default_refute_receive_timeout,
    do: Application.get_env(:commanded, :refute_receive_event_timeout, 1_000)
end
