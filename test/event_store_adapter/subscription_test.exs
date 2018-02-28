defmodule Commanded.EventStore.Adapter.SubscriptionTest do
  use Commanded.StorageCase

  alias Commanded.EventStore
  alias Commanded.EventStore.EventData
  alias Commanded.Helpers.{ProcessHelper, Wait}

  defmodule(BankAccountOpened, do: defstruct([:account_number, :initial_balance]))

  defmodule Subscriber do
    use GenServer

    alias Commanded.EventStore

    defmodule State do
      defstruct received_events: [],
                subscribed?: false,
                subscription: nil
    end

    alias Subscriber.State

    def start_link, do: GenServer.start_link(__MODULE__, %State{})

    def init(%State{} = state) do
      {:ok, subscription} = EventStore.subscribe_to_all_streams("subscriber", self(), :origin)

      {:ok, %State{state | subscription: subscription}}
    end

    def subscribed?(subscriber), do: GenServer.call(subscriber, :subscribed?)

    def received_events(subscriber), do: GenServer.call(subscriber, :received_events)

    def handle_call(:subscribed?, _from, %State{subscribed?: subscribed?} = state) do
      {:reply, subscribed?, state}
    end

    def handle_call(:received_events, _from, %State{received_events: received_events} = state) do
      {:reply, received_events, state}
    end

    def handle_info({:subscribed, subscription}, %State{subscription: subscription} = state) do
      {:noreply, %State{state | subscribed?: true}}
    end

    def handle_info({:events, events}, %State{} = state) do
      %State{received_events: received_events, subscription: subscription} = state

      state = %State{state | received_events: received_events ++ events}

      EventStore.ack_event(subscription, List.last(events))

      {:noreply, state}
    end
  end

  describe "transient subscription to single stream" do
    test "should receive events appended to the stream" do
      stream_uuid = UUID.uuid4()

      assert :ok = EventStore.subscribe(stream_uuid)

      {:ok, 1} = EventStore.append_to_stream(stream_uuid, 0, build_events(1))

      received_events = assert_receive_events(1, from: 1)
      assert Enum.map(received_events, &(&1.stream_id)) == [stream_uuid]
      assert Enum.map(received_events, &(&1.stream_version)) == [1]

      {:ok, 3} = EventStore.append_to_stream(stream_uuid, 1, build_events(2))

      received_events = assert_receive_events(2, from: 2)
      assert Enum.map(received_events, &(&1.stream_id)) == [stream_uuid, stream_uuid]
      assert Enum.map(received_events, &(&1.stream_version)) == [2, 3]

      {:ok, 6} = EventStore.append_to_stream(stream_uuid, 3, build_events(3))

      received_events = assert_receive_events(3, from: 4)
      assert Enum.map(received_events, &(&1.stream_id)) == [stream_uuid, stream_uuid, stream_uuid]
      assert Enum.map(received_events, &(&1.stream_version)) == [4, 5, 6]

      refute_receive {:events, _received_events}
    end

    test "should not receive events appended to another stream" do
      stream_uuid = UUID.uuid4()
      another_stream_uuid = UUID.uuid4()

      assert :ok = EventStore.subscribe(stream_uuid)

      {:ok, 1} = EventStore.append_to_stream(another_stream_uuid, 0, build_events(1))
      {:ok, 3} = EventStore.append_to_stream(another_stream_uuid, 1, build_events(2))

      refute_receive {:events, _received_events}
    end
  end

  describe "subscribe to all streams" do
    test "should receive `:subscribed` message once subscribed" do
      {:ok, subscription} = EventStore.subscribe_to_all_streams("subscriber", self(), :origin)

      assert_receive {:subscribed, ^subscription}
    end

    test "should receive events appended to any stream" do
      {:ok, subscription} = EventStore.subscribe_to_all_streams("subscriber", self(), :origin)

      assert_receive {:subscribed, ^subscription}

      {:ok, 1} = EventStore.append_to_stream("stream1", 0, build_events(1))
      {:ok, 2} = EventStore.append_to_stream("stream2", 0, build_events(2))
      {:ok, 3} = EventStore.append_to_stream("stream3", 0, build_events(3))

      assert_receive_events(subscription, 1, from: 1)
      assert_receive_events(subscription, 2, from: 2)
      assert_receive_events(subscription, 3, from: 4)

      refute_receive({:events, _events})
    end

    test "should skip existing events when subscribing from current position" do
      {:ok, 1} = EventStore.append_to_stream("stream1", 0, build_events(1))
      {:ok, 2} = EventStore.append_to_stream("stream2", 0, build_events(2))

      wait_for_event_store()

      {:ok, subscription} = EventStore.subscribe_to_all_streams("subscriber", self(), :current)

      assert_receive {:subscribed, ^subscription}
      refute_receive({:events, _events})

      {:ok, 3} = EventStore.append_to_stream("stream3", 0, build_events(3))

      assert_receive_events(subscription, 3, from: 4)

      refute_receive({:events, _events})
    end

    test "should prevent duplicate subscriptions" do
      {:ok, _subscription} = EventStore.subscribe_to_all_streams("subscriber", self(), :origin)

      assert {:error, :subscription_already_exists} ==
               EventStore.subscribe_to_all_streams("subscriber", self(), :origin)
    end
  end

  describe "catch-up subscription" do
    test "should receive any existing events" do
      {:ok, 1} = EventStore.append_to_stream("stream1", 0, build_events(1))
      {:ok, 2} = EventStore.append_to_stream("stream2", 0, build_events(2))

      wait_for_event_store()

      {:ok, subscription} = EventStore.subscribe_to_all_streams("subscriber", self(), :origin)

      assert_receive {:subscribed, ^subscription}

      assert_receive_events(subscription, 1, from: 1)
      assert_receive_events(subscription, 2, from: 2)

      {:ok, 3} = EventStore.append_to_stream("stream3", 0, build_events(3))

      assert_receive_events(subscription, 3, from: 4)
      refute_receive({:events, _events})
    end
  end

  describe "unsubscribe from all streams" do
    test "should not receive further events appended to any stream" do
      {:ok, subscription} = EventStore.subscribe_to_all_streams("subscriber", self(), :origin)

      assert_receive {:subscribed, ^subscription}

      {:ok, 1} = EventStore.append_to_stream("stream1", 0, build_events(1))

      assert_receive_events(subscription, 1, from: 1)

      :ok = EventStore.unsubscribe_from_all_streams("subscriber")

      {:ok, 2} = EventStore.append_to_stream("stream2", 0, build_events(2))
      {:ok, 3} = EventStore.append_to_stream("stream3", 0, build_events(3))

      refute_receive({:events, _events})
    end
  end

  describe "resume subscription" do
    test "should remember last seen event number when subscription resumes" do
      {:ok, 1} = EventStore.append_to_stream("stream1", 0, build_events(1))
      {:ok, 2} = EventStore.append_to_stream("stream2", 0, build_events(2))

      {:ok, subscriber} = Subscriber.start_link()

      wait_until(fn ->
        assert Subscriber.subscribed?(subscriber)
        received_events = Subscriber.received_events(subscriber)
        assert length(received_events) == 3
      end)

      # wait for last `ack`
      :timer.sleep(event_store_wait(200))

      ProcessHelper.shutdown(subscriber)

      wait_for_event_store()

      {:ok, subscriber} = Subscriber.start_link()

      wait_until(fn ->
        assert Subscriber.subscribed?(subscriber)
      end)

      received_events = Subscriber.received_events(subscriber)
      assert length(received_events) == 0

      {:ok, 1} = EventStore.append_to_stream("stream3", 0, build_events(1))

      wait_until(fn ->
        received_events = Subscriber.received_events(subscriber)
        assert length(received_events) == 1
      end)
    end
  end

  defp wait_until(assertion) do
    Wait.until(event_store_wait(1_000), assertion)
  end

  defp assert_receive_events(subscription, expected_count, opts) do
    assert_receive_events(expected_count, Keyword.put(opts, :subscription, subscription))
  end

  defp assert_receive_events(expected_count, opts) do
    from_event_number = Keyword.get(opts, :from, 1)

    assert_receive {:events, received_events}

    received_events
    |> Enum.with_index(from_event_number)
    |> Enum.each(fn {received_event, expected_event_number} ->
      assert received_event.event_number == expected_event_number
    end)

    case Keyword.get(opts, :subscription) do
      nil -> :ok
      subscription -> EventStore.ack_event(subscription, List.last(received_events))
    end

    case expected_count - length(received_events) do
      0 ->
        received_events

      remaining when remaining > 0 ->
        received_events ++
          assert_receive_events(
            remaining,
            Keyword.put(opts, :from, from_event_number + length(received_events))
          )

      remaining when remaining < 0 ->
        flunk("Received #{remaining} more event(s) than expected")
    end
  end

  defp build_event(account_number) do
    %EventData{
      causation_id: UUID.uuid4(),
      correlation_id: UUID.uuid4(),
      event_type: "Elixir.Commanded.EventStore.Adapter.SubscriptionTest.BankAccountOpened",
      data: %BankAccountOpened{account_number: account_number, initial_balance: 1_000},
      metadata: %{"user_id" => "test"}
    }
  end

  defp build_events(count) do
    for account_number <- 1..count, do: build_event(account_number)
  end

  defp wait_for_event_store do
    case event_store_wait() do
      nil -> :ok
      wait -> :timer.sleep(wait)
    end
  end

  defp event_store_wait(default \\ nil),
    do: Application.get_env(:commanded, :event_store_wait, default)
end
