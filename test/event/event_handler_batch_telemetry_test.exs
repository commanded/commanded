defmodule Commanded.Event.EventHandlerBatchTelemetryTest do
  use ExUnit.Case

  alias Commanded.Application.Config
  alias Commanded.Event.Handler
  alias Commanded.EventStore.Subscription

  # Test support code
  alias Commanded.Helpers.EventFactory
  alias Commanded.Event.{BatchHandler, ErrorHandlingBatchHandler}
  alias Commanded.Event.ReplyEvent
  alias Commanded.Event.EventHandlerBatchTelemetryTest.MockAdapter

  setup do
    attach_telemetry()
    :ok
  end

  describe "batch event handler telemetry" do
    test "should emit `[:commanded, :event, :batch, :stop]` telemetry from :ok" do
      events = [
        %ReplyEvent{reply_to: self(), value: 1},
        %ReplyEvent{reply_to: self(), value: 2}
      ]

      metadata = %{"key" => "value"}
      recorded_events = EventFactory.map_to_recorded_events(events, 1, metadata: metadata)
      state = setup_state(BatchHandler)

      {:noreply, _state} = Handler.handle_info({:events, recorded_events}, state)

      assert_receive {[:commanded, :event, :batch, :start], _measurements, _metadata}

      assert_receive {[:commanded, :event, :batch, :stop], _measurements, metadata}
      assert metadata.event_count == 2

      refute_received {[:commanded, :event, :batch, :exception], _measurements, _metadata}
    end

    test "should emit `[:commanded, :event, :batch, :stop]` telemetry from :error" do
      events = [
        %ReplyEvent{reply_to: self(), value: :error},
        %ReplyEvent{reply_to: self(), value: :error}
      ]

      metadata = %{"key" => "value"}
      recorded_events = EventFactory.map_to_recorded_events(events, 1, metadata: metadata)
      state = setup_state(BatchHandler)

      {:stop, :bad_value, _state} = Handler.handle_info({:events, recorded_events}, state)

      assert_receive {[:commanded, :event, :batch, :start], _measurements, _metadata}
      assert_receive {[:commanded, :event, :batch, :stop], _measurements, _metadata}
      refute_received {[:commanded, :event, :batch, :exception], _measurements, _metadata}
    end

    test "should include count of successfully processed events when erroring on a specific event" do
      events = [
        %ReplyEvent{reply_to: self(), value: 1},
        %ReplyEvent{reply_to: self(), value: 2},
        %ReplyEvent{reply_to: self(), value: :error},
        %ReplyEvent{reply_to: self(), value: 4},
      ]

      metadata = %{"key" => "value"}
      recorded_events = EventFactory.map_to_recorded_events(events, 1, metadata: metadata)
      state = setup_state(BatchHandler)

      Handler.handle_info({:events, recorded_events}, state)

      assert_receive {[:commanded, :event, :batch, :start], _measurements, metadata}
      assert metadata.event_count == 4

      assert_receive {[:commanded, :event, :batch, :stop], _measurements, metadata}
      assert metadata.event_count == 2
    end

    test "should emit `[:commanded, :event, :batch, :exception]` telemetry from thrown exception" do
      events = [
        %ReplyEvent{reply_to: self(), value: :error},
        %ReplyEvent{reply_to: self(), value: :error}
      ]

      metadata = %{"key" => "value"}
      recorded_events = EventFactory.map_to_recorded_events(events, 1, metadata: metadata)
      state = setup_state(ErrorHandlingBatchHandler)

      {:noreply, {:error, _reason, _stacktrace}} = Handler.handle_info({:events, recorded_events}, state)

      assert_receive {[:commanded, :event, :batch, :start], _measurements, _metadata}
      refute_received {[:commanded, :event, :batch, :stop], _measurements, _metadata}
      assert_receive {[:commanded, :event, :batch, :exception], _measurements, _metadata}
    end
  end

  defp setup_state(handler_module) do
    Config.associate(self(), __MODULE__, event_store: {MockAdapter, nil})

    %Handler{
      subscription:
        struct(Subscription,
          application: __MODULE__,
          subscription_pid: self()
        ),
      handler_callback: :batch,
      handler_module: handler_module,
      consistency: :eventual,
      last_seen_event: 0
    }
  end

  defp attach_telemetry do
    :telemetry.attach_many(
      "test-handler",
      [
        [:commanded, :event, :batch, :start],
        [:commanded, :event, :batch, :stop],
        [:commanded, :event, :batch, :exception]
      ],
      fn event_name, measurements, metadata, reply_to ->
        send(reply_to, {event_name, measurements, metadata})
      end,
      self()
    )

    on_exit(fn ->
      :telemetry.detach("test-handler")
    end)
  end

  defmodule MockAdapter do
    def ack_event(nil, subscription_pid, event) do
      send(subscription_pid, {:acked, event})
      :ok
    end
  end
end
