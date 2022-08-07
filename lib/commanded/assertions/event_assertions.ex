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

  alias Commanded.{EventStore, UUID}
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
  def assert_receive_event(application, event_type, assertion_fn)
      when is_function(assertion_fn, 1) or is_function(assertion_fn, 2) do
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
  def assert_receive_event(application, event_type, predicate_fn, assertion_fn)
      when is_function(assertion_fn, 1) or is_function(assertion_fn, 2) do
    unless Code.ensure_loaded?(event_type) do
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

  Refute that `ExampleEvent` is produced by given anonymous function:

    refute_receive_event(ExampleApp, ExampleEvent, fn ->
      :ok = MyApp.dispatch(command)
    end)

  Refute that `ExampleEvent` is produced by `some_func/0` function:

    refute_receive_event(ExampleApp, ExampleEvent, &some_func/0)

  Refute that `ExampleEvent` matching given `event_matches?/1` predicate function
  is produced by `some_func/0` function:

      refute_receive_event(ExampleApp, ExampleEvent, &some_func/0,
        predicate: &event_matches?/1
      )

  Refute that `ExampleEvent` matching given anonymous predicate function
  is produced by `some_func/0` function:

      refute_receive_event(ExampleApp, ExampleEvent, &some_func/0,
        predicate: fn event -> event.value == 1 end
      )

  Refute that `ExampleEvent` produced by `some_func/0` function is published to
  a given stream:

      refute_receive_event(ExampleApp, ExampleEvent, &some_func/0,
        predicate: fn event -> event.value == 1 end,
        stream: "foo-1234"
      )

  """

  def refute_receive_event(application, event_type, refute_fn, opts \\ [])
      when is_function(refute_fn, 0) do
    predicate_fn = Keyword.get(opts, :predicate) || fn _event -> true end
    timeout = Keyword.get(opts, :timeout, default_refute_receive_timeout())
    subscription_opts = Keyword.take(opts, [:stream]) |> Keyword.put(:start_from, :current)
    reply_to = self()
    ref = make_ref()

    # Start a task to subscribe and verify received events
    task =
      Task.async(fn ->
        with_subscription(
          application,
          fn subscription ->
            send(reply_to, {:subscribed, ref})

            do_refute_receive_event(application, subscription, event_type, predicate_fn)
          end,
          subscription_opts
        )
      end)

    # Wait until subscription has subscribed before executing refute function,
    # otherwise we might not receive a matching event.
    assert_receive {:subscribed, ^ref}, default_receive_timeout()

    refute_fn.()

    case Task.yield(task, timeout) || Task.shutdown(task) do
      {:ok, :ok} -> :ok
      {:ok, {:error, event}} -> flunk("Unexpectedly received event: " <> inspect(event))
      {:exit, error} -> flunk("Encountered an error: " <> inspect(error))
      nil -> :ok
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
  def with_subscription(application, callback_fn, opts \\ [])
      when is_function(callback_fn, 1) do
    subscription_name = UUID.uuid4()
    stream = Keyword.get(opts, :stream, :all)
    start_from = Keyword.get(opts, :start_from, :origin)

    {:ok, subscription} =
      EventStore.subscribe_to(application, stream, subscription_name, self(), start_from)

    assert_receive {:subscribed, ^subscription}, default_receive_timeout()

    try do
      callback_fn.(subscription)
    after
      :ok = EventStore.unsubscribe(application, subscription)
      :ok = EventStore.delete_subscription(application, stream, subscription_name)
    end
  end

  defp do_assert_receive(application, subscription, event_type, predicate_fn, assertion_fn) do
    assert_receive {:events, received_events}, default_receive_timeout()

    case find_expected_event(received_events, event_type, predicate_fn) do
      %RecordedEvent{data: data} = expected_event ->
        args =
          cond do
            is_function(assertion_fn, 1) -> [data]
            is_function(assertion_fn, 2) -> [data, expected_event]
          end

        apply(assertion_fn, args)

      nil ->
        :ok = ack_events(application, subscription, received_events)

        do_assert_receive(application, subscription, event_type, predicate_fn, assertion_fn)
    end
  end

  defp do_refute_receive_event(application, subscription, event_type, predicate_fn) do
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
      %RecordedEvent{data: %{__struct__: ^event_type} = data} = received_event ->
        args =
          cond do
            is_function(predicate_fn, 1) -> [data]
            is_function(predicate_fn, 2) -> [data, received_event]
          end

        apply(predicate_fn, args)

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
