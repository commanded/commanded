defmodule Commanded.SubscriptionsTest do
	use ExUnit.Case

  alias Commanded.EventStore.RecordedEvent
  alias Commanded.Subscriptions

  setup do
    _ = Subscriptions.start_link()

    on_exit fn ->
      case Process.whereis(Subscriptions) do
        nil -> :ok
        pid -> Commanded.Helpers.Process.shutdown(pid)
      end
    end

    :ok
  end

  describe "register event handler" do
    test "should be registered" do
      :ok = Subscriptions.register("handler1", :strong)
      :ok = Subscriptions.register("handler2", :eventual)
      :ok = Subscriptions.register("handler3", :strong)

      assert Subscriptions.all() |> Enum.sort() == ["handler1", "handler3"]
    end

    test "should ack event" do
      :ok = Subscriptions.register("handler1", :strong)

      :ok = Subscriptions.ack_event("handler1", :strong, %RecordedEvent{stream_id: "stream1", stream_version: 2})

      assert Subscriptions.handled?("stream1", 1)
      assert Subscriptions.handled?("stream1", 2)
    end

    test "should require all subscriptions to ack event" do
      :ok = Subscriptions.register("handler1", :strong)
      :ok = Subscriptions.register("handler2", :strong)

      :ok = Subscriptions.ack_event("handler1", :strong, %RecordedEvent{stream_id: "stream1", stream_version: 2})
      refute Subscriptions.handled?("stream1", 1)

      :ok = Subscriptions.ack_event("handler2", :strong, %RecordedEvent{stream_id: "stream1", stream_version: 1})
      assert Subscriptions.handled?("stream1", 1)
      refute Subscriptions.handled?("stream1", 2)

      :ok = Subscriptions.ack_event("handler2", :strong, %RecordedEvent{stream_id: "stream1", stream_version: 2})
      assert Subscriptions.handled?("stream1", 1)
      assert Subscriptions.handled?("stream1", 2)
    end
  end

  describe "notify subscribers" do
    test "should immediately succeed when no registered handlers" do
      assert :ok == Subscriptions.wait_for("stream1", 2)
    end

    test "should immediately succeed when waited event has already been ack'd" do
      :ok = Subscriptions.register("handler", :strong)

      :ok = Subscriptions.ack_event("handler", :strong, %RecordedEvent{stream_id: "stream1", stream_version: 1})
      :ok = Subscriptions.ack_event("handler", :strong, %RecordedEvent{stream_id: "stream1", stream_version: 2})

      assert :ok == Subscriptions.wait_for("stream1", 2)
    end

    test "should succeed when waited event is ack'd" do
      :ok = Subscriptions.register("handler", :strong)

      wait_task = Task.async(fn ->
        Subscriptions.wait_for("stream1", 2, 1_000)
      end)

      :ok = Subscriptions.ack_event("handler", :strong, %RecordedEvent{stream_id: "stream1", stream_version: 1})
      :ok = Subscriptions.ack_event("handler", :strong, %RecordedEvent{stream_id: "stream1", stream_version: 2})

      assert :ok == Task.await(wait_task, 1_000)
    end

    test "should ignore events before requested" do
      :ok = Subscriptions.register("handler", :strong)

      :ok = Subscriptions.ack_event("handler", :strong, %RecordedEvent{event_number: 1})

      assert {:error, :timeout} == Subscriptions.wait_for(2, 100)
    end

    test "should wait for all subscriptions to ack event" do
      :ok = Subscriptions.register("handler1", :strong)
      :ok = Subscriptions.register("handler2", :strong)
      :ok = Subscriptions.register("handler3", :eventual)

      refute Subscriptions.handled?("stream1", 2)

      :ok = Subscriptions.ack_event("handler1", :strong, %RecordedEvent{stream_id: "stream1", stream_version: 1})
      :ok = Subscriptions.ack_event("handler1", :strong, %RecordedEvent{stream_id: "stream1", stream_version: 2})

      refute Subscriptions.handled?("stream1", 2)

      :ok = Subscriptions.ack_event("handler2", :strong, %RecordedEvent{stream_id: "stream1", stream_version: 1})
      :ok = Subscriptions.ack_event("handler2", :strong, %RecordedEvent{stream_id: "stream1", stream_version: 2})

      assert Subscriptions.handled?("stream1", 2)
    end

    test "should allow subscriptions to skip events when ack" do
      :ok = Subscriptions.register("handler", :strong)

      refute Subscriptions.handled?("stream1", 2)

      :ok = Subscriptions.ack_event("handler", :strong, %RecordedEvent{stream_id: "stream1", stream_version: 4})

      assert Subscriptions.handled?("stream1", 2)
    end
  end

  describe "expire stream acks" do
    test "should expire stale acks" do
      :ok = Subscriptions.register("handler1", :strong)
      :ok = Subscriptions.ack_event("handler1", :strong, %RecordedEvent{stream_id: "stream1", stream_version: 1})

      assert Subscriptions.handled?("stream1", 1)

      pid = Process.whereis(Subscriptions)
      send(pid, {:purge_expired_streams, 0})

      refute Subscriptions.handled?("stream1", 1)
    end

    test "should not expire fresh acks" do
      :ok = Subscriptions.register("handler1", :strong)
      :ok = Subscriptions.ack_event("handler1", :strong, %RecordedEvent{stream_id: "stream1", stream_version: 1})

      assert Subscriptions.handled?("stream1", 1)

      pid = Process.whereis(Subscriptions)
      send(pid, {:purge_expired_streams, 1_000})

      assert Subscriptions.handled?("stream1", 1)
    end
  end
end
