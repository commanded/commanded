defmodule Commanded.EventStore.TelemetryTest do
  use ExUnit.Case

  alias Commanded.DefaultApp
  alias Commanded.EventStore
  alias Commanded.EventStore.RecordedEvent
  alias Commanded.EventStore.SnapshotData
  alias Commanded.Middleware.Commands.IncrementCount
  alias Commanded.Middleware.Commands.RaiseError

  setup do
    start_supervised!(DefaultApp)
    attach_telemetry()

    :ok
  end

  defmodule TestRouter do
    use Commanded.Commands.Router

    alias Commanded.Middleware.Commands.CommandHandler
    alias Commanded.Middleware.Commands.CounterAggregateRoot

    dispatch IncrementCount,
      to: CommandHandler,
      aggregate: CounterAggregateRoot,
      identity: :aggregate_uuid

    dispatch RaiseError,
      to: CommandHandler,
      aggregate: CounterAggregateRoot,
      identity: :aggregate_uuid
  end

  describe "snapshotting telemetry events" do
    test "emit `[:commanded, :event_store, :record_snapshot, :start | :stop]` event" do
      assert :ok = EventStore.record_snapshot(DefaultApp, %SnapshotData{})

      assert_receive {[:commanded, :event_store, :record_snapshot, :start], 1, _meas, _meta}
      assert_receive {[:commanded, :event_store, :record_snapshot, :stop], 2, _meas, _meta}
    end

    test "emit `[:commanded, :event_store, :read_snapshot, :start | :stop]` event" do
      assert {:error, :snapshot_not_found} = EventStore.read_snapshot(DefaultApp, UUID.uuid4())

      assert_receive {[:commanded, :event_store, :read_snapshot, :start], 1, _meas, _meta}
      assert_receive {[:commanded, :event_store, :read_snapshot, :stop], 2, _meas, _meta}
    end

    test "emit `[:commanded, :event_store, :delete_snapshot, :start | :stop]` event" do
      assert :ok = EventStore.delete_snapshot(DefaultApp, UUID.uuid4())

      assert_receive {[:commanded, :event_store, :delete_snapshot, :start], 1, _meas, _meta}
      assert_receive {[:commanded, :event_store, :delete_snapshot, :stop], 2, _meas, _meta}
    end
  end

  describe "streaming telemetry events" do
    test "emit `[:commanded, :event_store, :stream_forward, :start | :stop]` event" do
      assert {:error, :stream_not_found} = EventStore.stream_forward(DefaultApp, UUID.uuid4())

      assert_receive {[:commanded, :event_store, :stream_forward, :start], 1, _meas, _meta}
      assert_receive {[:commanded, :event_store, :stream_forward, :stop], 2, _meas, _meta}
    end
  end

  describe "ack_event telemetry events" do
    test "emit `[:commanded, :event_store, :ack_event, :start | :stop]` event" do
      assert :ok = EventStore.ack_event(DefaultApp, self(), %RecordedEvent{})

      assert_receive {[:commanded, :event_store, :ack_event, :start], 1, _meas, _meta}
      assert_receive {[:commanded, :event_store, :ack_event, :stop], 2, _meas, _meta}
    end
  end

  describe "subscription telemetry events" do
    test "emit `[:commanded, :event_store, :subscribe, :start | :stop]` event" do
      assert :ok = EventStore.subscribe(DefaultApp, UUID.uuid4())

      assert_receive {[:commanded, :event_store, :subscribe, :start], 1, _meas, _meta}
      assert_receive {[:commanded, :event_store, :subscribe, :stop], 2, _meas, _meta}
    end

    test "emit `[:commanded, :event_store, :subscribe_to, :start | :stop]` event" do
      assert {:ok, pid} = EventStore.subscribe_to(DefaultApp, :all, "Test", self(), :current)

      assert_receive {:subscribed, ^pid}
      assert_receive {[:commanded, :event_store, :subscribe_to, :start], 1, _meas, _meta}
      assert_receive {[:commanded, :event_store, :subscribe_to, :stop], 2, _meas, _meta}
    end

    test "emit `[:commanded, :event_store, :unsubscribe, :start | :stop]` event" do
      assert {:ok, pid} = EventStore.subscribe_to(DefaultApp, :all, "Test", self(), :current)

      assert_receive {:subscribed, ^pid}

      assert_receive {[:commanded, :event_store, :subscribe_to, :start], 1, _meas, _meta}
      assert_receive {[:commanded, :event_store, :subscribe_to, :stop], 2, _meas, _meta}

      assert :ok = EventStore.unsubscribe(DefaultApp, pid)

      assert_receive {[:commanded, :event_store, :unsubscribe, :start], 3, _meas, _meta}
      assert_receive {[:commanded, :event_store, :unsubscribe, :stop], 4, _meas, _meta}
    end

    test "emit `[:commanded, :event_store, :delete_subscription, :start | :stop]` event" do
      assert {:error, :subscription_not_found} =
               EventStore.delete_subscription(DefaultApp, :all, "Test")

      assert_receive {[:commanded, :event_store, :delete_subscription, :start], 1, _meas, _meta}
      assert_receive {[:commanded, :event_store, :delete_subscription, :stop], 2, _meas, _meta}
    end
  end

  defp attach_telemetry do
    agent = start_supervised!({Agent, fn -> 1 end})
    handler = :"#{__MODULE__}-handler"

    events = [
      :record_snapshot,
      :read_snapshot,
      :delete_snapshot,
      :stream_forward,
      :subscribe,
      :subscribe_to,
      :unsubscribe,
      :delete_subscription,
      :ack_event
    ]

    :telemetry.attach_many(
      handler,
      Enum.flat_map(events, fn event ->
        [
          [:commanded, :event_store, event, :start],
          [:commanded, :event_store, event, :stop]
        ]
      end),
      fn event_name, measurements, metadata, reply_to ->
        num = Agent.get_and_update(agent, fn n -> {n, n + 1} end)
        send(reply_to, {event_name, num, measurements, metadata})
      end,
      self()
    )

    on_exit(fn ->
      :telemetry.detach(handler)
    end)
  end
end
