defmodule Commanded.EventStore.SubscriptionTestCase do
  import Commanded.SharedTestCase

  define_tests do
    alias Commanded.EventStore.{EventData, RecordedEvent, Subscriber}
    alias Commanded.Helpers.ProcessHelper
    alias Commanded.UUID

    defmodule BankAccountOpened do
      @derive Jason.Encoder
      defstruct [:account_number, :initial_balance]
    end

    describe "transient subscription to single stream" do
      test "should receive events appended to the stream", %{
        event_store: event_store,
        event_store_meta: event_store_meta
      } do
        stream_uuid = UUID.uuid4()

        assert :ok = event_store.subscribe(event_store_meta, stream_uuid)

        :ok = event_store.append_to_stream(event_store_meta, stream_uuid, 0, build_events(1))

        received_events = assert_receive_events(event_store, event_store_meta, count: 1, from: 1)

        for %RecordedEvent{} = event <- received_events do
          assert event.stream_id == stream_uuid
          assert %DateTime{} = event.created_at
        end

        assert Enum.map(received_events, & &1.stream_version) == [1]

        :ok = event_store.append_to_stream(event_store_meta, stream_uuid, 1, build_events(2))

        received_events = assert_receive_events(event_store, event_store_meta, count: 2, from: 2)

        for %RecordedEvent{} = event <- received_events do
          assert event.stream_id == stream_uuid
          assert %DateTime{} = event.created_at
        end

        assert Enum.map(received_events, & &1.stream_version) == [2, 3]

        :ok = event_store.append_to_stream(event_store_meta, stream_uuid, 3, build_events(3))

        received_events = assert_receive_events(event_store, event_store_meta, count: 3, from: 4)

        for %RecordedEvent{} = event <- received_events do
          assert event.stream_id == stream_uuid
          assert %DateTime{} = event.created_at
        end

        assert Enum.map(received_events, & &1.stream_version) == [4, 5, 6]

        refute_receive {:events, _received_events}
      end

      test "should not receive events appended to another stream", %{
        event_store: event_store,
        event_store_meta: event_store_meta
      } do
        stream_uuid = UUID.uuid4()
        another_stream_uuid = UUID.uuid4()

        assert :ok = event_store.subscribe(event_store_meta, stream_uuid)

        :ok =
          event_store.append_to_stream(event_store_meta, another_stream_uuid, 0, build_events(1))

        :ok =
          event_store.append_to_stream(event_store_meta, another_stream_uuid, 1, build_events(2))

        refute_receive {:events, _received_events}
      end
    end

    describe "transient subscription to all streams" do
      test "should receive events appended to any stream", %{
        event_store: event_store,
        event_store_meta: event_store_meta
      } do
        assert :ok = event_store.subscribe(event_store_meta, :all)

        :ok = event_store.append_to_stream(event_store_meta, "stream1", 0, build_events(1))

        received_events = assert_receive_events(event_store, event_store_meta, count: 1, from: 1)
        assert Enum.map(received_events, & &1.stream_id) == ["stream1"]
        assert Enum.map(received_events, & &1.stream_version) == [1]

        :ok = event_store.append_to_stream(event_store_meta, "stream2", 0, build_events(2))

        received_events = assert_receive_events(event_store, event_store_meta, count: 2, from: 2)
        assert Enum.map(received_events, & &1.stream_id) == ["stream2", "stream2"]
        assert Enum.map(received_events, & &1.stream_version) == [1, 2]

        :ok = event_store.append_to_stream(event_store_meta, "stream3", 0, build_events(3))

        received_events = assert_receive_events(event_store, event_store_meta, count: 3, from: 4)
        assert Enum.map(received_events, & &1.stream_id) == ["stream3", "stream3", "stream3"]
        assert Enum.map(received_events, & &1.stream_version) == [1, 2, 3]

        :ok = event_store.append_to_stream(event_store_meta, "stream1", 1, build_events(2))

        received_events = assert_receive_events(event_store, event_store_meta, count: 2, from: 7)
        assert Enum.map(received_events, & &1.stream_id) == ["stream1", "stream1"]
        assert Enum.map(received_events, & &1.stream_version) == [2, 3]

        refute_receive {:events, _received_events}
      end
    end

    describe "persistent subscription to a single stream" do
      test "should receive `:subscribed` message once subscribed", %{
        event_store: event_store,
        event_store_meta: event_store_meta
      } do
        {:ok, subscription} =
          event_store.subscribe_to(event_store_meta, "stream1", "subscriber", self(), :origin, [])

        assert_receive {:subscribed, ^subscription}
      end

      test "should receive events appended to stream", %{
        event_store: event_store,
        event_store_meta: event_store_meta
      } do
        {:ok, subscription} =
          event_store.subscribe_to(event_store_meta, "stream1", "subscriber", self(), :origin, [])

        assert_receive {:subscribed, ^subscription}

        :ok = event_store.append_to_stream(event_store_meta, "stream1", 0, build_events(1))
        :ok = event_store.append_to_stream(event_store_meta, "stream1", 1, build_events(2))
        :ok = event_store.append_to_stream(event_store_meta, "stream1", 3, build_events(3))

        assert_receive_events(event_store, event_store_meta, subscription, count: 1, from: 1)
        assert_receive_events(event_store, event_store_meta, subscription, count: 2, from: 2)
        assert_receive_events(event_store, event_store_meta, subscription, count: 3, from: 4)

        refute_receive {:events, _received_events}
      end

      test "should not receive events appended to another stream", %{
        event_store: event_store,
        event_store_meta: event_store_meta
      } do
        {:ok, subscription} =
          event_store.subscribe_to(event_store_meta, "stream1", "subscriber", self(), :origin, [])

        :ok = event_store.append_to_stream(event_store_meta, "stream1", 0, build_events(1))
        :ok = event_store.append_to_stream(event_store_meta, "stream2", 0, build_events(2))
        :ok = event_store.append_to_stream(event_store_meta, "stream3", 0, build_events(3))

        assert_receive_events(event_store, event_store_meta, subscription, count: 1, from: 1)
        refute_receive {:events, _received_events}
      end

      test "should skip existing events when subscribing from current position", %{
        event_store: event_store,
        event_store_meta: event_store_meta
      } do
        :ok = event_store.append_to_stream(event_store_meta, "stream1", 0, build_events(1))
        :ok = event_store.append_to_stream(event_store_meta, "stream1", 1, build_events(2))

        wait_for_event_store()

        {:ok, subscription} =
          event_store.subscribe_to(
            event_store_meta,
            "stream1",
            "subscriber",
            self(),
            :current,
            []
          )

        assert_receive {:subscribed, ^subscription}
        refute_receive {:events, _events}

        :ok = event_store.append_to_stream(event_store_meta, "stream1", 3, build_events(3))
        :ok = event_store.append_to_stream(event_store_meta, "stream2", 0, build_events(3))
        :ok = event_store.append_to_stream(event_store_meta, "stream3", 0, build_events(3))

        assert_receive_events(event_store, event_store_meta, subscription, count: 3, from: 4)
        refute_receive {:events, _events}
      end

      test "should receive events already appended to stream", %{
        event_store: event_store,
        event_store_meta: event_store_meta
      } do
        :ok = event_store.append_to_stream(event_store_meta, "stream1", 0, build_events(1))
        :ok = event_store.append_to_stream(event_store_meta, "stream2", 0, build_events(2))
        :ok = event_store.append_to_stream(event_store_meta, "stream3", 0, build_events(3))

        {:ok, subscription} =
          event_store.subscribe_to(event_store_meta, "stream3", "subscriber", self(), :origin, [])

        assert_receive {:subscribed, ^subscription}

        assert_receive_events(event_store, event_store_meta, subscription, count: 3, from: 1)

        :ok = event_store.append_to_stream(event_store_meta, "stream3", 3, build_events(1))
        :ok = event_store.append_to_stream(event_store_meta, "stream3", 4, build_events(1))

        assert_receive_events(event_store, event_store_meta, subscription, count: 2, from: 4)
        refute_receive {:events, _received_events}
      end

      test "should prevent duplicate subscriptions", %{
        event_store: event_store,
        event_store_meta: event_store_meta
      } do
        {:ok, _subscription} =
          event_store.subscribe_to(event_store_meta, "stream1", "subscriber", self(), :origin, [])

        assert {:error, :subscription_already_exists} ==
                 event_store.subscribe_to(
                   event_store_meta,
                   "stream1",
                   "subscriber",
                   self(),
                   :origin,
                   []
                 )
      end
    end

    describe "persistent subscription to all streams" do
      test "should receive `:subscribed` message once subscribed", %{
        event_store: event_store,
        event_store_meta: event_store_meta
      } do
        {:ok, subscription} =
          event_store.subscribe_to(event_store_meta, :all, "subscriber", self(), :origin, [])

        assert_receive {:subscribed, ^subscription}
      end

      test "should receive events appended to any stream", %{
        event_store: event_store,
        event_store_meta: event_store_meta
      } do
        {:ok, subscription} =
          event_store.subscribe_to(event_store_meta, :all, "subscriber", self(), :origin, [])

        assert_receive {:subscribed, ^subscription}

        :ok = event_store.append_to_stream(event_store_meta, "stream1", 0, build_events(1))
        :ok = event_store.append_to_stream(event_store_meta, "stream2", 0, build_events(2))
        :ok = event_store.append_to_stream(event_store_meta, "stream3", 0, build_events(3))

        assert_receive_events(event_store, event_store_meta, subscription, count: 1, from: 1)
        assert_receive_events(event_store, event_store_meta, subscription, count: 2, from: 2)
        assert_receive_events(event_store, event_store_meta, subscription, count: 3, from: 4)

        refute_receive {:events, _received_events}
      end

      test "should receive events already appended to any stream", %{
        event_store: event_store,
        event_store_meta: event_store_meta
      } do
        :ok = event_store.append_to_stream(event_store_meta, "stream1", 0, build_events(1))
        :ok = event_store.append_to_stream(event_store_meta, "stream2", 0, build_events(2))

        wait_for_event_store()

        {:ok, subscription} =
          event_store.subscribe_to(event_store_meta, :all, "subscriber", self(), :origin, [])

        assert_receive {:subscribed, ^subscription}

        assert_receive_events(event_store, event_store_meta, subscription, count: 1, from: 1)
        assert_receive_events(event_store, event_store_meta, subscription, count: 2, from: 2)

        :ok = event_store.append_to_stream(event_store_meta, "stream3", 0, build_events(3))

        assert_receive_events(event_store, event_store_meta, subscription, count: 3, from: 4)
        refute_receive {:events, _received_events}
      end

      test "should skip existing events when subscribing from current position", %{
        event_store: event_store,
        event_store_meta: event_store_meta
      } do
        :ok = event_store.append_to_stream(event_store_meta, "stream1", 0, build_events(1))
        :ok = event_store.append_to_stream(event_store_meta, "stream2", 0, build_events(2))

        wait_for_event_store()

        {:ok, subscription} =
          event_store.subscribe_to(event_store_meta, :all, "subscriber", self(), :current, [])

        assert_receive {:subscribed, ^subscription}
        refute_receive {:events, _received_events}

        :ok = event_store.append_to_stream(event_store_meta, "stream3", 0, build_events(3))

        assert_receive_events(event_store, event_store_meta, subscription, count: 3, from: 4)

        refute_receive {:events, _received_events}
      end

      test "should prevent duplicate subscriptions", %{
        event_store: event_store,
        event_store_meta: event_store_meta
      } do
        {:ok, _subscription} =
          event_store.subscribe_to(event_store_meta, :all, "subscriber", self(), :origin, [])

        assert {:error, :subscription_already_exists} ==
                 event_store.subscribe_to(
                   event_store_meta,
                   :all,
                   "subscriber",
                   self(),
                   :origin,
                   []
                 )
      end
    end

    describe "persistent subscription concurrency" do
      test "should allow multiple subscribers to single subscription", %{
        event_store: event_store,
        event_store_meta: event_store_meta
      } do
        {:ok, _subscriber1} =
          Subscriber.start_link(event_store, event_store_meta, self(), concurrency_limit: 2)

        {:ok, _subscriber2} =
          Subscriber.start_link(event_store, event_store_meta, self(), concurrency_limit: 2)

        assert_receive {:subscribed, _subscription1}
        assert_receive {:subscribed, _subscription2}
        refute_receive {:subscribed, _subscription}
      end

      test "should prevent too many subscribers to single subscription", %{
        event_store: event_store,
        event_store_meta: event_store_meta
      } do
        {:ok, _subscriber} = Subscriber.start_link(event_store, event_store_meta, self())

        assert {:error, :subscription_already_exists} =
                 Subscriber.start_link(event_store, event_store_meta, self())
      end

      test "should prevent too many subscribers to subscription with concurrency limit", %{
        event_store: event_store,
        event_store_meta: event_store_meta
      } do
        {:ok, _subscriber1} =
          Subscriber.start_link(event_store, event_store_meta, self(), concurrency_limit: 3)

        {:ok, _subscriber2} =
          Subscriber.start_link(event_store, event_store_meta, self(), concurrency_limit: 3)

        {:ok, _subscriber3} =
          Subscriber.start_link(event_store, event_store_meta, self(), concurrency_limit: 3)

        assert {:error, :too_many_subscribers} =
                 Subscriber.start_link(event_store, event_store_meta, self(), concurrency_limit: 3)
      end

      test "should distribute events amongst subscribers", %{
        event_store: event_store,
        event_store_meta: event_store_meta
      } do
        {:ok, _subscriber1} =
          Subscriber.start_link(event_store, event_store_meta, self(), concurrency_limit: 3)

        {:ok, _subscriber2} =
          Subscriber.start_link(event_store, event_store_meta, self(), concurrency_limit: 3)

        {:ok, _subscriber2} =
          Subscriber.start_link(event_store, event_store_meta, self(), concurrency_limit: 3)

        assert_receive {:subscribed, _subscription1}
        assert_receive {:subscribed, _subscription2}
        assert_receive {:subscribed, _subscription3}

        :ok = event_store.append_to_stream(event_store_meta, "stream1", 0, build_events(6))

        subscribers =
          for n <- 1..6 do
            assert_receive {:events, subscriber, [%RecordedEvent{event_number: ^n}] = events}

            :ok = Subscriber.ack(subscriber, events)

            subscriber
          end
          |> Enum.uniq()

        refute_receive {:events, _subscriber, _received_events}

        assert length(subscribers) == 3
      end

      test "should distribute events to subscribers using optional partition by function", %{
        event_store: event_store,
        event_store_meta: event_store_meta
      } do
        opts = [
          concurrency_limit: 3,
          partition_by: fn %RecordedEvent{stream_id: stream_id} -> stream_id end
        ]

        {:ok, _subscriber1} = Subscriber.start_link(event_store, event_store_meta, self(), opts)
        {:ok, _subscriber2} = Subscriber.start_link(event_store, event_store_meta, self(), opts)
        {:ok, _subscriber3} = Subscriber.start_link(event_store, event_store_meta, self(), opts)

        assert_receive {:subscribed, _subscription1}
        assert_receive {:subscribed, _subscription2}
        assert_receive {:subscribed, _subscription3}

        :ok = event_store.append_to_stream(event_store_meta, "stream0", 0, build_events(2))
        :ok = event_store.append_to_stream(event_store_meta, "stream1", 0, build_events(2))
        :ok = event_store.append_to_stream(event_store_meta, "stream2", 0, build_events(2))

        :ok = event_store.append_to_stream(event_store_meta, "stream0", 2, build_events(2))
        :ok = event_store.append_to_stream(event_store_meta, "stream1", 2, build_events(2))
        :ok = event_store.append_to_stream(event_store_meta, "stream2", 2, build_events(2))

        :ok = event_store.append_to_stream(event_store_meta, "stream0", 4, build_events(1))
        :ok = event_store.append_to_stream(event_store_meta, "stream1", 4, build_events(1))
        :ok = event_store.append_to_stream(event_store_meta, "stream2", 4, build_events(1))

        assert_receive {:events, subscriber1,
                        [%RecordedEvent{event_number: 1, stream_id: "stream0"}] = events1}

        assert_receive {:events, subscriber2,
                        [%RecordedEvent{event_number: 3, stream_id: "stream1"}] = events2}

        assert_receive {:events, subscriber3,
                        [%RecordedEvent{event_number: 5, stream_id: "stream2"}] = events3}

        refute_receive {:events, _subscriber, _received_events}

        :ok = Subscriber.ack(subscriber1, events1)
        :ok = Subscriber.ack(subscriber2, events2)
        :ok = Subscriber.ack(subscriber3, events3)

        assert_receive {:events, ^subscriber1,
                        [%RecordedEvent{event_number: 2, stream_id: "stream0"}] = events4}

        assert_receive {:events, ^subscriber2,
                        [%RecordedEvent{event_number: 4, stream_id: "stream1"}] = events5}

        assert_receive {:events, ^subscriber3,
                        [%RecordedEvent{event_number: 6, stream_id: "stream2"}] = events6}

        refute_receive {:events, _subscriber, _received_events}

        :ok = Subscriber.ack(subscriber1, events4)
        :ok = Subscriber.ack(subscriber2, events5)
        :ok = Subscriber.ack(subscriber3, events6)

        assert_receive {:events, ^subscriber1,
                        [%RecordedEvent{event_number: 7, stream_id: "stream0"}] = events7}

        assert_receive {:events, ^subscriber2,
                        [%RecordedEvent{event_number: 9, stream_id: "stream1"}] = events8}

        assert_receive {:events, ^subscriber3,
                        [%RecordedEvent{event_number: 11, stream_id: "stream2"}] = events9}

        refute_receive {:events, _subscriber, _received_events}

        :ok = Subscriber.ack(subscriber1, events7)
        :ok = Subscriber.ack(subscriber2, events8)
        :ok = Subscriber.ack(subscriber3, events9)

        assert_receive {:events, ^subscriber1,
                        [%RecordedEvent{event_number: 8, stream_id: "stream0"}] = events10}

        assert_receive {:events, ^subscriber2,
                        [%RecordedEvent{event_number: 10, stream_id: "stream1"}] = events11}

        assert_receive {:events, ^subscriber3,
                        [%RecordedEvent{event_number: 12, stream_id: "stream2"}] = events12}

        refute_receive {:events, _subscriber, _received_events}

        :ok = Subscriber.ack(subscriber1, events10)
        :ok = Subscriber.ack(subscriber2, events11)
        :ok = Subscriber.ack(subscriber3, events12)

        assert_receive {:events, ^subscriber1,
                        [%RecordedEvent{event_number: 13, stream_id: "stream0"}] = events13}

        assert_receive {:events, ^subscriber2,
                        [%RecordedEvent{event_number: 14, stream_id: "stream1"}] = events14}

        assert_receive {:events, ^subscriber3,
                        [%RecordedEvent{event_number: 15, stream_id: "stream2"}] = events15}

        refute_receive {:events, _subscriber, _received_events}

        :ok = Subscriber.ack(subscriber1, events13)
        :ok = Subscriber.ack(subscriber2, events14)
        :ok = Subscriber.ack(subscriber3, events15)

        refute_receive {:events, _subscriber, _received_events}
      end

      test "should exclude stopped subscriber from receiving events", %{
        event_store: event_store,
        event_store_meta: event_store_meta
      } do
        {:ok, subscriber1} =
          Subscriber.start_link(event_store, event_store_meta, self(), concurrency_limit: 2)

        {:ok, subscriber2} =
          Subscriber.start_link(event_store, event_store_meta, self(), concurrency_limit: 2)

        assert_receive {:subscribed, _subscription1}
        assert_receive {:subscribed, _subscription2}

        :ok = event_store.append_to_stream(event_store_meta, "stream1", 0, build_events(2))

        for n <- 1..2 do
          assert_receive {:events, subscriber, [%RecordedEvent{event_number: ^n}] = events}

          :ok = Subscriber.ack(subscriber, events)
        end

        stop_subscriber(subscriber1)

        :ok = event_store.append_to_stream(event_store_meta, "stream2", 0, build_events(2))

        for n <- 3..4 do
          assert_receive {:events, ^subscriber2, [%RecordedEvent{event_number: ^n}] = events}

          :ok = Subscriber.ack(subscriber2, events)
        end

        stop_subscriber(subscriber2)

        :ok = event_store.append_to_stream(event_store_meta, "stream3", 0, build_events(2))

        refute_receive {:events, _subscriber, _received_events}
      end
    end

    describe "unsubscribe from all streams" do
      test "should not receive further events appended to any stream", %{
        event_store: event_store,
        event_store_meta: event_store_meta
      } do
        {:ok, subscription} =
          event_store.subscribe_to(event_store_meta, :all, "subscriber", self(), :origin, [])

        assert_receive {:subscribed, ^subscription}

        :ok = event_store.append_to_stream(event_store_meta, "stream1", 0, build_events(1))

        assert_receive_events(event_store, event_store_meta, subscription, count: 1, from: 1)

        :ok = unsubscribe(event_store, event_store_meta, subscription)

        :ok = event_store.append_to_stream(event_store_meta, "stream2", 0, build_events(2))
        :ok = event_store.append_to_stream(event_store_meta, "stream3", 0, build_events(3))

        refute_receive {:events, _received_events}
      end

      test "should resume subscription when subscribing again", %{
        event_store: event_store,
        event_store_meta: event_store_meta
      } do
        {:ok, subscription1} =
          event_store.subscribe_to(event_store_meta, :all, "subscriber", self(), :origin, [])

        assert_receive {:subscribed, ^subscription1}

        :ok = event_store.append_to_stream(event_store_meta, "stream1", 0, build_events(1))

        assert_receive_events(event_store, event_store_meta, subscription1, count: 1, from: 1)

        :ok = unsubscribe(event_store, event_store_meta, subscription1)

        {:ok, subscription2} =
          event_store.subscribe_to(event_store_meta, :all, "subscriber", self(), :origin, [])

        :ok = event_store.append_to_stream(event_store_meta, "stream2", 0, build_events(2))

        assert_receive {:subscribed, ^subscription2}
        assert_receive_events(event_store, event_store_meta, subscription2, count: 2, from: 2)
      end
    end

    describe "delete subscription" do
      test "should be deleted", %{event_store: event_store, event_store_meta: event_store_meta} do
        {:ok, subscription1} =
          event_store.subscribe_to(event_store_meta, :all, "subscriber", self(), :origin, [])

        assert_receive {:subscribed, ^subscription1}

        :ok = event_store.append_to_stream(event_store_meta, "stream1", 0, build_events(1))

        assert_receive_events(event_store, event_store_meta, subscription1, count: 1, from: 1)

        :ok = unsubscribe(event_store, event_store_meta, subscription1)

        assert :ok = event_store.delete_subscription(event_store_meta, :all, "subscriber")
      end

      test "should create new subscription after deletion", %{
        event_store: event_store,
        event_store_meta: event_store_meta
      } do
        {:ok, subscription1} =
          event_store.subscribe_to(event_store_meta, :all, "subscriber", self(), :origin, [])

        assert_receive {:subscribed, ^subscription1}

        :ok = event_store.append_to_stream(event_store_meta, "stream1", 0, build_events(1))

        assert_receive_events(event_store, event_store_meta, subscription1, count: 1, from: 1)

        :ok = unsubscribe(event_store, event_store_meta, subscription1)

        :ok = event_store.delete_subscription(event_store_meta, :all, "subscriber")

        :ok = event_store.append_to_stream(event_store_meta, "stream2", 0, build_events(2))

        refute_receive {:events, _received_events}

        {:ok, subscription2} =
          event_store.subscribe_to(event_store_meta, :all, "subscriber", self(), :origin, [])

        # Should receive all events as subscription has been recreated from `:origin`
        assert_receive {:subscribed, ^subscription2}
        assert_receive_events(event_store, event_store_meta, subscription2, count: 1, from: 1)
        assert_receive_events(event_store, event_store_meta, subscription2, count: 2, from: 2)
      end
    end

    describe "resume subscription" do
      test "should resume from checkpoint", %{
        event_store: event_store,
        event_store_meta: event_store_meta
      } do
        :ok = event_store.append_to_stream(event_store_meta, "stream1", 0, build_events(1))
        :ok = event_store.append_to_stream(event_store_meta, "stream2", 0, build_events(1))

        {:ok, subscriber1} = Subscriber.start_link(event_store, event_store_meta, self())

        assert_receive {:subscribed, _subscription}
        assert_receive {:events, ^subscriber1, received_events}
        assert length(received_events) == 1
        assert Enum.map(received_events, & &1.stream_id) == ["stream1"]

        :ok = Subscriber.ack(subscriber1, received_events)

        assert_receive {:events, ^subscriber1, received_events}
        assert length(received_events) == 1
        assert Enum.map(received_events, & &1.stream_id) == ["stream2"]

        :ok = Subscriber.ack(subscriber1, received_events)

        stop_subscriber(subscriber1)

        {:ok, subscriber2} = Subscriber.start_link(event_store, event_store_meta, self())

        assert_receive {:subscribed, _subscription}
        refute_receive {:events, _subscriber, _received_events}

        :ok = event_store.append_to_stream(event_store_meta, "stream3", 0, build_events(1))

        assert_receive {:events, ^subscriber2, received_events}
        assert length(received_events) == 1
        assert Enum.map(received_events, & &1.stream_id) == ["stream3"]

        :ok = Subscriber.ack(subscriber2, received_events)

        refute_receive {:events, _subscriber, _received_events}
      end

      test "should resume subscription from last successful ack", %{
        event_store: event_store,
        event_store_meta: event_store_meta
      } do
        :ok = event_store.append_to_stream(event_store_meta, "stream1", 0, build_events(1))
        :ok = event_store.append_to_stream(event_store_meta, "stream2", 0, build_events(1))

        {:ok, subscriber1} = Subscriber.start_link(event_store, event_store_meta, self())

        assert_receive {:subscribed, _subscription}

        assert_receive {:events, ^subscriber1,
                        [%RecordedEvent{event_number: 1, stream_id: "stream1"}] = received_events}

        :ok = Subscriber.ack(subscriber1, received_events)

        assert_receive {:events, ^subscriber1,
                        [%RecordedEvent{event_number: 2, stream_id: "stream2"}]}

        stop_subscriber(subscriber1)

        {:ok, subscriber2} = Subscriber.start_link(event_store, event_store_meta, self())

        assert_receive {:subscribed, _subscription}

        # Receive event #2 again because it wasn't ack'd
        assert_receive {:events, ^subscriber2,
                        [%RecordedEvent{event_number: 2, stream_id: "stream2"}] = received_events}

        :ok = Subscriber.ack(subscriber2, received_events)

        :ok = event_store.append_to_stream(event_store_meta, "stream3", 0, build_events(1))

        assert_receive {:events, ^subscriber2,
                        [%RecordedEvent{event_number: 3, stream_id: "stream3"}] = received_events}

        :ok = Subscriber.ack(subscriber2, received_events)

        refute_receive {:events, _subscriber, _received_events}
      end
    end

    describe "subscription process" do
      test "should not stop subscriber process when subscription down", %{
        event_store: event_store,
        event_store_meta: event_store_meta
      } do
        {:ok, subscriber} = Subscriber.start_link(event_store, event_store_meta, self())

        ref = Process.monitor(subscriber)

        assert_receive {:subscribed, subscription}

        ProcessHelper.shutdown(subscription)

        refute Process.alive?(subscription)
        assert Process.alive?(subscriber)
        refute_receive {:DOWN, ^ref, :process, ^subscriber, _reason}
      end

      test "should stop subscription process when subscriber down", %{
        event_store: event_store,
        event_store_meta: event_store_meta
      } do
        {:ok, subscriber} = Subscriber.start_link(event_store, event_store_meta, self())

        assert_receive {:subscribed, subscription}

        ref = Process.monitor(subscription)

        stop_subscriber(subscriber)

        assert_receive {:DOWN, ^ref, :process, ^subscription, _reason}
      end
    end

    defp unsubscribe(event_store, event_store_meta, subscription) do
      :ok = event_store.unsubscribe(event_store_meta, subscription)

      wait_for_event_store()
    end

    defp stop_subscriber(subscriber) do
      ProcessHelper.shutdown(subscriber)

      wait_for_event_store()
    end

    # Optionally wait for the event store
    defp wait_for_event_store do
      case event_store_wait() do
        nil -> :ok
        wait -> :timer.sleep(wait)
      end
    end

    defp assert_receive_events(event_store, event_store_meta, subscription, opts) do
      opts = Keyword.put(opts, :subscription, subscription)

      assert_receive_events(event_store, event_store_meta, opts)
    end

    defp assert_receive_events(event_store, event_store_meta, opts) do
      expected_count = Keyword.fetch!(opts, :count)
      from_event_number = Keyword.get(opts, :from, 1)

      assert_receive {:events, received_events}
      assert_received_events(received_events, from_event_number)

      case Keyword.get(opts, :subscription) do
        subscription when is_pid(subscription) ->
          last_event = List.last(received_events)

          event_store.ack_event(event_store_meta, subscription, last_event)

        nil ->
          :ok
      end

      case expected_count - length(received_events) do
        0 ->
          received_events

        remaining when remaining > 0 ->
          opts =
            opts
            |> Keyword.put(:from, from_event_number + length(received_events))
            |> Keyword.put(:count, remaining)

          received_events ++ assert_receive_events(event_store, event_store_meta, opts)

        remaining when remaining < 0 ->
          flunk("Received #{abs(remaining)} more event(s) than expected")
      end
    end

    defp assert_received_events(received_events, from_event_number) do
      received_events
      |> Enum.with_index(from_event_number)
      |> Enum.each(fn {received_event, expected_event_number} ->
        assert received_event.event_number == expected_event_number
      end)
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
