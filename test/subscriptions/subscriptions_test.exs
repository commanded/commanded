defmodule Commanded.SubscriptionsTest do
  use Commanded.StorageCase

  alias Commanded.DefaultApp
  alias Commanded.EventStore.RecordedEvent
  alias Commanded.Subscriptions

  setup do
    start_supervised!(DefaultApp)
    :ok
  end

  describe "register event handler" do
    test "should be registered" do
      :ok = Subscriptions.register(DefaultApp, "handler1", :strong)
      :ok = Subscriptions.register(DefaultApp, "handler2", :eventual)
      :ok = Subscriptions.register(DefaultApp, "handler3", :strong)

      assert Subscriptions.all(DefaultApp) == [{"handler3", self()}, {"handler1", self()}]
    end

    test "should not remove PID when process terminates" do
      pid =
        spawn_link(fn ->
          :ok = Subscriptions.register(DefaultApp, "handler1", :strong)
        end)

      ref = Process.monitor(pid)
      assert_receive {:DOWN, ^ref, :process, _, :normal}

      assert Subscriptions.all(DefaultApp) == [{"handler1", pid}]
    end

    test "should replace registered subscription PID" do
      reply_to = self()

      pid1 =
        spawn_link(fn ->
          :ok = Subscriptions.register(DefaultApp, "handler1", :strong)

          send(reply_to, {:handler, self()})
        end)

      assert_receive {:handler, ^pid1}
      assert Subscriptions.all(DefaultApp) == [{"handler1", pid1}]

      pid2 =
        spawn_link(fn ->
          :ok = Subscriptions.register(DefaultApp, "handler1", :strong)

          send(reply_to, {:handler, self()})
        end)

      assert_receive {:handler, ^pid2}
      assert Subscriptions.all(DefaultApp) == [{"handler1", pid2}]
    end

    test "should ack event" do
      :ok = Subscriptions.register(DefaultApp, "handler1", :strong)

      :ok =
        Subscriptions.ack_event(DefaultApp, "handler1", :strong, %RecordedEvent{
          stream_id: "stream1",
          stream_version: 2
        })

      assert Subscriptions.handled?(DefaultApp, "stream1", 1)
      assert Subscriptions.handled?(DefaultApp, "stream1", 2)
    end

    test "should require all subscriptions to ack event" do
      :ok = Subscriptions.register(DefaultApp, "handler1", :strong)
      :ok = Subscriptions.register(DefaultApp, "handler2", :strong)

      :ok =
        Subscriptions.ack_event(DefaultApp, "handler1", :strong, %RecordedEvent{
          stream_id: "stream1",
          stream_version: 2
        })

      refute Subscriptions.handled?(DefaultApp, "stream1", 1)

      :ok =
        Subscriptions.ack_event(DefaultApp, "handler2", :strong, %RecordedEvent{
          stream_id: "stream1",
          stream_version: 1
        })

      assert Subscriptions.handled?(DefaultApp, "stream1", 1)
      refute Subscriptions.handled?(DefaultApp, "stream1", 2)

      :ok =
        Subscriptions.ack_event(DefaultApp, "handler2", :strong, %RecordedEvent{
          stream_id: "stream1",
          stream_version: 2
        })

      assert Subscriptions.handled?(DefaultApp, "stream1", 1)
      assert Subscriptions.handled?(DefaultApp, "stream1", 2)
    end

    test "should ignore current process as handler" do
      :ok = Subscriptions.register(DefaultApp, "handler1", :strong)

      # current process should not block handler
      assert Subscriptions.handled?(DefaultApp, "stream1", 1, exclude: [self()])
    end
  end

  describe "notify subscribers" do
    test "should immediately succeed when no registered handlers" do
      assert :ok == Subscriptions.wait_for(DefaultApp, "stream1", 2)
    end

    test "should immediately succeed when waited event has already been ack'd" do
      :ok = Subscriptions.register(DefaultApp, "handler", :strong)

      :ok =
        Subscriptions.ack_event(DefaultApp, "handler", :strong, %RecordedEvent{
          stream_id: "stream1",
          stream_version: 1
        })

      :ok =
        Subscriptions.ack_event(DefaultApp, "handler", :strong, %RecordedEvent{
          stream_id: "stream1",
          stream_version: 2
        })

      assert :ok == Subscriptions.wait_for(DefaultApp, "stream1", 2)
    end

    test "should immediately succeed when excluding handler process" do
      :ok = Subscriptions.register(DefaultApp, "handler", :strong)

      assert :ok == Subscriptions.wait_for(DefaultApp, "stream1", 2, exclude: [self()])
    end

    test "should succeed when waited event is ack'd" do
      :ok = Subscriptions.register(DefaultApp, "handler", :strong)

      wait_task =
        Task.async(fn ->
          Subscriptions.wait_for(DefaultApp, "stream1", 2, [], 1_000)
        end)

      :ok =
        Subscriptions.ack_event(DefaultApp, "handler", :strong, %RecordedEvent{
          stream_id: "stream1",
          stream_version: 1
        })

      :ok =
        Subscriptions.ack_event(DefaultApp, "handler", :strong, %RecordedEvent{
          stream_id: "stream1",
          stream_version: 2
        })

      assert :ok == Task.await(wait_task, 1_000)
    end

    test "should ignore events before requested" do
      :ok = Subscriptions.register(DefaultApp, "handler", :strong)

      :ok =
        Subscriptions.ack_event(DefaultApp, "handler", :strong, %RecordedEvent{event_number: 1})

      assert {:error, :timeout} == Subscriptions.wait_for(DefaultApp, 2, 100)
    end

    test "should wait for all subscriptions to ack event" do
      :ok = Subscriptions.register(DefaultApp, "handler1", :strong)
      :ok = Subscriptions.register(DefaultApp, "handler2", :strong)
      :ok = Subscriptions.register(DefaultApp, "handler3", :eventual)

      refute Subscriptions.handled?(DefaultApp, "stream1", 2)

      :ok =
        Subscriptions.ack_event(DefaultApp, "handler1", :strong, %RecordedEvent{
          stream_id: "stream1",
          stream_version: 1
        })

      :ok =
        Subscriptions.ack_event(DefaultApp, "handler1", :strong, %RecordedEvent{
          stream_id: "stream1",
          stream_version: 2
        })

      refute Subscriptions.handled?(DefaultApp, "stream1", 2)

      :ok =
        Subscriptions.ack_event(DefaultApp, "handler2", :strong, %RecordedEvent{
          stream_id: "stream1",
          stream_version: 1
        })

      :ok =
        Subscriptions.ack_event(DefaultApp, "handler2", :strong, %RecordedEvent{
          stream_id: "stream1",
          stream_version: 2
        })

      assert Subscriptions.handled?(DefaultApp, "stream1", 2)
    end

    test "should allow subscriptions to skip events when ack" do
      :ok = Subscriptions.register(DefaultApp, "handler", :strong)

      refute Subscriptions.handled?(DefaultApp, "stream1", 2)

      :ok =
        Subscriptions.ack_event(DefaultApp, "handler", :strong, %RecordedEvent{
          stream_id: "stream1",
          stream_version: 4
        })

      assert Subscriptions.handled?(DefaultApp, "stream1", 2)
    end

    test "should allow per-handler consistency" do
      :ok = Subscriptions.register(DefaultApp, "handler1", :strong)
      :ok = Subscriptions.register(DefaultApp, "handler2", :strong)

      :ok =
        Subscriptions.ack_event(DefaultApp, "handler1", :strong, %RecordedEvent{
          stream_id: "stream1",
          stream_version: 2
        })

      refute Subscriptions.handled?(DefaultApp, "stream1", 2)
      assert :ok == Subscriptions.wait_for(DefaultApp, "stream1", 2, consistency: ["handler1"])
    end

    test "should wait for each configured handler consistency" do
      :ok = Subscriptions.register(DefaultApp, "handler1", :strong)
      :ok = Subscriptions.register(DefaultApp, "handler2", :strong)
      :ok = Subscriptions.register(DefaultApp, "handler3", :strong)
      :ok = Subscriptions.register(DefaultApp, "handler3", :eventual)

      :ok =
        Subscriptions.ack_event(DefaultApp, "handler1", :strong, %RecordedEvent{
          stream_id: "stream1",
          stream_version: 2
        })

      :ok =
        Subscriptions.ack_event(DefaultApp, "handler2", :strong, %RecordedEvent{
          stream_id: "stream1",
          stream_version: 2
        })

      refute Subscriptions.handled?(DefaultApp, "stream1", 2)

      assert Subscriptions.handled?(DefaultApp, "stream1", 2,
               consistency: ["handler1", "handler2"]
             )

      refute Subscriptions.handled?(DefaultApp, "stream1", 2,
               consistency: ["handler1", "handler2", "handler3"]
             )

      assert Subscriptions.handled?(DefaultApp, "stream1", 2,
               consistency: ["handler1", "handler2", "handler4"]
             )

      assert :ok ==
               Subscriptions.wait_for(DefaultApp, "stream1", 2,
                 consistency: ["handler1", "handler2"]
               )

      assert {:error, :timeout} ==
               Subscriptions.wait_for(
                 DefaultApp,
                 "stream1",
                 2,
                 [consistency: ["handler1", "handler2", "handler3"]],
                 100
               )
    end
  end

  describe "expire stream acks" do
    test "should expire stale acks" do
      :ok = Subscriptions.register(DefaultApp, "handler1", :strong)

      :ok =
        Subscriptions.ack_event(DefaultApp, "handler1", :strong, %RecordedEvent{
          stream_id: "stream1",
          stream_version: 1
        })

      assert Subscriptions.handled?(DefaultApp, "stream1", 1)

      pid = Process.whereis(DefaultApp.Commanded.Subscriptions)
      send(pid, {:purge_expired_streams, 0})

      refute Subscriptions.handled?(DefaultApp, "stream1", 1)
    end

    test "should not expire fresh acks" do
      :ok = Subscriptions.register(DefaultApp, "handler1", :strong)

      :ok =
        Subscriptions.ack_event(DefaultApp, "handler1", :strong, %RecordedEvent{
          stream_id: "stream1",
          stream_version: 1
        })

      assert Subscriptions.handled?(DefaultApp, "stream1", 1)

      pid = Process.whereis(DefaultApp.Commanded.Subscriptions)
      send(pid, {:purge_expired_streams, 1_000})

      assert Subscriptions.handled?(DefaultApp, "stream1", 1)
    end
  end
end
