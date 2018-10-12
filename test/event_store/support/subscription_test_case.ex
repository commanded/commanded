defmodule Commanded.EventStore.SubscriptionTestCase do
  import Commanded.SharedTestCase

  define_tests do
    alias Commanded.EventStore
    alias Commanded.EventStore.{EventData, Subscriber}
    alias Commanded.Helpers.{ProcessHelper, Wait}

    defmodule BankAccountOpened do
      defstruct [:account_number, :initial_balance]
    end

    describe "transient subscription to single stream" do
      test "should receive events appended to the stream" do
        stream_uuid = UUID.uuid4()

        assert :ok = EventStore.subscribe(stream_uuid)

        :ok = EventStore.append_to_stream(stream_uuid, 0, build_events(1))

        received_events = assert_receive_events(1, from: 1)
        assert Enum.map(received_events, & &1.stream_id) == [stream_uuid]
        assert Enum.map(received_events, & &1.stream_version) == [1]

        :ok = EventStore.append_to_stream(stream_uuid, 1, build_events(2))

        received_events = assert_receive_events(2, from: 2)
        assert Enum.map(received_events, & &1.stream_id) == [stream_uuid, stream_uuid]
        assert Enum.map(received_events, & &1.stream_version) == [2, 3]

        :ok = EventStore.append_to_stream(stream_uuid, 3, build_events(3))

        received_events = assert_receive_events(3, from: 4)

        assert Enum.map(received_events, & &1.stream_id) == [
                 stream_uuid,
                 stream_uuid,
                 stream_uuid
               ]

        assert Enum.map(received_events, & &1.stream_version) == [4, 5, 6]

        refute_receive {:events, _received_events}
      end

      test "should not receive events appended to another stream" do
        stream_uuid = UUID.uuid4()
        another_stream_uuid = UUID.uuid4()

        assert :ok = EventStore.subscribe(stream_uuid)

        :ok = EventStore.append_to_stream(another_stream_uuid, 0, build_events(1))
        :ok = EventStore.append_to_stream(another_stream_uuid, 1, build_events(2))

        refute_receive {:events, _received_events}
      end
    end

    describe "transient subscription to all streams" do
      test "should receive events appended to any stream" do
        assert :ok = EventStore.subscribe(:all)

        :ok = EventStore.append_to_stream("stream1", 0, build_events(1))

        received_events = assert_receive_events(1, from: 1)
        assert Enum.map(received_events, & &1.stream_id) == ["stream1"]
        assert Enum.map(received_events, & &1.stream_version) == [1]

        :ok = EventStore.append_to_stream("stream2", 0, build_events(2))

        received_events = assert_receive_events(2, from: 2)
        assert Enum.map(received_events, & &1.stream_id) == ["stream2", "stream2"]
        assert Enum.map(received_events, & &1.stream_version) == [1, 2]

        :ok = EventStore.append_to_stream("stream3", 0, build_events(3))

        received_events = assert_receive_events(3, from: 4)
        assert Enum.map(received_events, & &1.stream_id) == ["stream3", "stream3", "stream3"]
        assert Enum.map(received_events, & &1.stream_version) == [1, 2, 3]

        :ok = EventStore.append_to_stream("stream1", 1, build_events(2))

        received_events = assert_receive_events(2, from: 7)
        assert Enum.map(received_events, & &1.stream_id) == ["stream1", "stream1"]
        assert Enum.map(received_events, & &1.stream_version) == [2, 3]

        refute_receive {:events, _received_events}
      end
    end

    describe "subscribe to single stream" do
      test "should receive `:subscribed` message once subscribed" do
        {:ok, subscription} = EventStore.subscribe_to("stream1", "subscriber", self(), :origin)

        assert_receive {:subscribed, ^subscription}
      end

      test "should receive events appended to stream" do
        {:ok, subscription} = EventStore.subscribe_to("stream1", "subscriber", self(), :origin)

        assert_receive {:subscribed, ^subscription}

        :ok = EventStore.append_to_stream("stream1", 0, build_events(1))
        :ok = EventStore.append_to_stream("stream1", 1, build_events(2))
        :ok = EventStore.append_to_stream("stream1", 3, build_events(3))

        assert_receive_events(subscription, 1, from: 1)
        assert_receive_events(subscription, 2, from: 2)
        assert_receive_events(subscription, 3, from: 4)

        refute_receive {:events, _received_events}
      end

      test "should not receive events appended to another stream" do
        {:ok, subscription} = EventStore.subscribe_to("stream1", "subscriber", self(), :origin)

        :ok = EventStore.append_to_stream("stream1", 0, build_events(1))
        :ok = EventStore.append_to_stream("stream2", 0, build_events(2))
        :ok = EventStore.append_to_stream("stream3", 0, build_events(3))

        assert_receive_events(subscription, 1, from: 1)
        refute_receive {:events, _received_events}
      end

      test "should skip existing events when subscribing from current position" do
        :ok = EventStore.append_to_stream("stream1", 0, build_events(1))
        :ok = EventStore.append_to_stream("stream1", 1, build_events(2))

        wait_for_event_store()

        {:ok, subscription} = EventStore.subscribe_to("stream1", "subscriber", self(), :current)

        assert_receive {:subscribed, ^subscription}
        refute_receive {:events, _events}

        :ok = EventStore.append_to_stream("stream1", 3, build_events(3))
        :ok = EventStore.append_to_stream("stream2", 0, build_events(3))
        :ok = EventStore.append_to_stream("stream3", 0, build_events(3))

        assert_receive_events(subscription, 3, from: 4)
        refute_receive {:events, _events}
      end

      test "should prevent duplicate subscriptions" do
        {:ok, _subscription} = EventStore.subscribe_to("stream1", "subscriber", self(), :origin)

        assert {:error, :subscription_already_exists} ==
                 EventStore.subscribe_to("stream1", "subscriber", self(), :origin)
      end
    end

    describe "subscribe to all streams" do
      test "should receive `:subscribed` message once subscribed" do
        {:ok, subscription} = EventStore.subscribe_to(:all, "subscriber", self(), :origin)

        assert_receive {:subscribed, ^subscription}
      end

      test "should receive events appended to any stream" do
        {:ok, subscription} = EventStore.subscribe_to(:all, "subscriber", self(), :origin)

        assert_receive {:subscribed, ^subscription}

        :ok = EventStore.append_to_stream("stream1", 0, build_events(1))
        :ok = EventStore.append_to_stream("stream2", 0, build_events(2))
        :ok = EventStore.append_to_stream("stream3", 0, build_events(3))

        assert_receive_events(subscription, 1, from: 1)
        assert_receive_events(subscription, 2, from: 2)
        assert_receive_events(subscription, 3, from: 4)

        refute_receive {:events, _received_events}
      end

      test "should skip existing events when subscribing from current position" do
        :ok = EventStore.append_to_stream("stream1", 0, build_events(1))
        :ok = EventStore.append_to_stream("stream2", 0, build_events(2))

        wait_for_event_store()

        {:ok, subscription} = EventStore.subscribe_to(:all, "subscriber", self(), :current)

        assert_receive {:subscribed, ^subscription}
        refute_receive {:events, _received_events}

        :ok = EventStore.append_to_stream("stream3", 0, build_events(3))

        assert_receive_events(subscription, 3, from: 4)

        refute_receive {:events, _received_events}
      end

      test "should prevent duplicate subscriptions" do
        {:ok, _subscription} = EventStore.subscribe_to(:all, "subscriber", self(), :origin)

        assert {:error, :subscription_already_exists} ==
                 EventStore.subscribe_to(:all, "subscriber", self(), :origin)
      end
    end

    describe "catch-up subscription" do
      test "should receive any existing events" do
        :ok = EventStore.append_to_stream("stream1", 0, build_events(1))
        :ok = EventStore.append_to_stream("stream2", 0, build_events(2))

        wait_for_event_store()

        {:ok, subscription} = EventStore.subscribe_to(:all, "subscriber", self(), :origin)

        assert_receive {:subscribed, ^subscription}

        assert_receive_events(subscription, 1, from: 1)
        assert_receive_events(subscription, 2, from: 2)

        :ok = EventStore.append_to_stream("stream3", 0, build_events(3))

        assert_receive_events(subscription, 3, from: 4)
        refute_receive {:events, _received_events}
      end
    end

    describe "unsubscribe from all streams" do
      test "should not receive further events appended to any stream" do
        {:ok, subscription} = EventStore.subscribe_to(:all, "subscriber", self(), :origin)

        assert_receive {:subscribed, ^subscription}

        :ok = EventStore.append_to_stream("stream1", 0, build_events(1))

        assert_receive_events(subscription, 1, from: 1)

        :ok = EventStore.unsubscribe(subscription)

        :ok = EventStore.append_to_stream("stream2", 0, build_events(2))
        :ok = EventStore.append_to_stream("stream3", 0, build_events(3))

        refute_receive {:events, _received_events}
      end
    end

    describe "resume subscription" do
      test "should remember last seen event number when subscription resumes" do
        :ok = EventStore.append_to_stream("stream1", 0, build_events(1))
        :ok = EventStore.append_to_stream("stream2", 0, build_events(2))

        {:ok, subscriber} = Subscriber.start_link()

        wait_until(fn ->
          assert Subscriber.subscribed?(subscriber)
          received_events = Subscriber.received_events(subscriber)
          assert length(received_events) == 3
        end)

        ProcessHelper.shutdown(subscriber)

        {:ok, subscriber} = Subscriber.start_link()

        wait_until(fn ->
          assert Subscriber.subscribed?(subscriber)
        end)

        received_events = Subscriber.received_events(subscriber)
        assert length(received_events) == 0

        :ok = EventStore.append_to_stream("stream3", 0, build_events(1))

        wait_until(fn ->
          received_events = Subscriber.received_events(subscriber)
          assert length(received_events) == 1
        end)
      end
    end

    defp wait_until(assertion) do
      Wait.until(event_store_wait(1_000), assertion)
    end

    defp wait_for_event_store do
      case event_store_wait() do
        nil -> :ok
        wait -> :timer.sleep(wait)
      end
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
        event_type: "#{__MODULE__}.BankAccountOpened",
        data: %BankAccountOpened{account_number: account_number, initial_balance: 1_000},
        metadata: %{"user_id" => "test"}
      }
    end

    defp build_events(count) do
      for account_number <- 1..count, do: build_event(account_number)
    end
  end
end
