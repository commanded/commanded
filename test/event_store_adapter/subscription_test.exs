defmodule Commanded.EventStore.Adapter.SubscriptionTest do
  use Commanded.StorageCase
  use Commanded.EventStore

  alias Commanded.EventStore.EventData
  alias Commanded.Helpers.Wait

  defmodule BankAccountOpened, do: defstruct [:account_number, :initial_balance]

  defmodule Subscriber do
    use GenServer
    use Commanded.EventStore

    defmodule State do
      defstruct [
        received_events: [],
        subscription: nil,
      ]
    end

    alias Subscriber.State

    def start_link do
      GenServer.start_link(__MODULE__, %State{})
    end

    def init(%State{} = state) do
      {:ok, subscription} = @event_store.subscribe_to_all_streams("subscriber", self(), :origin)

      state = %State{state |
        subscription: subscription,
      }

      {:ok, state}
    end

    def received_events(subscriber) do
      GenServer.call(subscriber, :received_events)
    end

    def handle_call(:received_events, _from, %State{received_events: received_events} = state) do
      {:reply, received_events, state}
    end

    def handle_info({:events, events}, %State{received_events: received_events, subscription: subscription} = state) do
      state = %State{state |
        received_events: Enum.concat(received_events, events),
      }

      @event_store.ack_event(subscription, List.last(events))

      {:noreply, state}
    end
  end

  describe "subscribe to all streams" do
    test "should receive events appended to any stream" do
      {:ok, subscription} = @event_store.subscribe_to_all_streams("subscriber", self(), :origin)

      {:ok, 1} = @event_store.append_to_stream("stream1", 0, build_events(1))
      {:ok, 2} = @event_store.append_to_stream("stream2", 0, build_events(2))
      {:ok, 3} = @event_store.append_to_stream("stream3", 0, build_events(3))

      assert_receive_events(subscription, 1)
      assert_receive_events(subscription, 2)
      assert_receive_events(subscription, 3)

      refute_receive({:events, _events})
    end

    test "should skip existing events when subscribing from current position" do
      {:ok, 1} = @event_store.append_to_stream("stream1", 0, build_events(1))
      {:ok, 2} = @event_store.append_to_stream("stream2", 0, build_events(2))

      {:ok, subscription} = @event_store.subscribe_to_all_streams("subscriber", self(), :current)

      refute_receive({:events, _events})

      {:ok, 3} = @event_store.append_to_stream("stream3", 0, build_events(3))

      assert_receive_events(subscription, 3)

      refute_receive({:events, _events})
    end

    test "should prevent duplicate subscriptions" do
      {:ok, _subscription} = @event_store.subscribe_to_all_streams("subscriber", self(), :origin)
      assert {:error, :subscription_already_exists} == @event_store.subscribe_to_all_streams("subscriber", self(), :origin)
    end
  end

  describe "catch-up subscription" do
    test "should receive any existing events" do
      {:ok, 1} = @event_store.append_to_stream("stream1", 0, build_events(1))
      {:ok, 2} = @event_store.append_to_stream("stream2", 0, build_events(2))

      {:ok, subscription} = @event_store.subscribe_to_all_streams("subscriber", self(), :origin)

      assert_receive_events(subscription, 1)
      assert_receive_events(subscription, 2)

      {:ok, 3} = @event_store.append_to_stream("stream3", 0, build_events(3))

      assert_receive_events(subscription, 3)

      refute_receive({:events, _events})
    end
  end

  describe "ubsubscribe from all streams" do
    test "should not receive further events appended to any stream" do
      {:ok, subscription} = @event_store.subscribe_to_all_streams("subscriber", self(), :origin)

      {:ok, 1} = @event_store.append_to_stream("stream1", 0, build_events(1))

      assert_receive_events(subscription, 1)

      :ok = @event_store.unsubscribe_from_all_streams("subscriber")

      {:ok, 2} = @event_store.append_to_stream("stream2", 0, build_events(2))
      {:ok, 3} = @event_store.append_to_stream("stream3", 0, build_events(3))

      refute_receive({:events, _events})
    end
  end

  describe "resume subscription" do
    test "should remember last seen event number when subscription resumes" do
      {:ok, 1} = @event_store.append_to_stream("stream1", 0, build_events(1))
      {:ok, 2} = @event_store.append_to_stream("stream2", 0, build_events(2))

      {:ok, subscriber} = Subscriber.start_link()

      Wait.until(fn ->
        received_events = Subscriber.received_events(subscriber)
        assert length(received_events) == 3
      end)

      # wait for last `ack`
      :timer.sleep(200)

      Commanded.Helpers.Process.shutdown(subscriber)
      {:ok, subscriber} = Subscriber.start_link()

      received_events = Subscriber.received_events(subscriber)
      assert length(received_events) == 0

      {:ok, 1} = @event_store.append_to_stream("stream3", 0, build_events(1))

      Wait.until(fn ->
        received_events = Subscriber.received_events(subscriber)
        assert length(received_events) == 1
      end)
    end
  end

  def assert_receive_events(subscription, expected_count) do
    assert_receive {:events, received_events}
    assert length(received_events) == expected_count

    @event_store.ack_event(subscription, List.last(received_events))
  end

  defp build_event(account_number) do
    %EventData{
      correlation_id: UUID.uuid4,
      event_type: "Elixir.Commanded.EventStore.Adapter.SubscriptionTest.BankAccountOpened",
      data: %BankAccountOpened{account_number: account_number, initial_balance: 1_000},
      metadata: %{}
    }
  end

  defp build_events(count) do
    for account_number <- 1..count, do: build_event(account_number)
  end
end
