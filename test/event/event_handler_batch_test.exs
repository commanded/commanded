defmodule Commanded.Event.EventHandlerBatchTest do
  use ExUnit.Case, async: true

  alias Commanded.Application.Config
  alias Commanded.Event.Handler
  alias Commanded.EventStore.Subscription

  # Test support code
  alias Commanded.Helpers.EventFactory
  alias Commanded.Event.{BatchHandler, ErrorHandlingBatchHandler}
  alias Commanded.Event.ReplyEvent
  alias Commanded.Event.EventHandlerBatchTest.MockAdapter
  alias Commanded.Event.ErrorAggregate.Events.ErrorEvent

  describe "batch handling" do
    test "should receive events in batches" do
      event1 = %ReplyEvent{reply_to: self(), value: 1}
      event2 = %ReplyEvent{reply_to: self(), value: 2}
      events = [event1, event2]

      metadata = %{"key" => "value"}
      recorded_events = EventFactory.map_to_recorded_events(events, 1, metadata: metadata)
      state = setup_state(BatchHandler)

      {:noreply, _state} = Handler.handle_info({:events, recorded_events}, state)

      assert_received {:batch, _pid, _events, _metadata}
    end
  end

  describe "failure handling with no error handler" do
    # See BatchHandler for how the special values in ReplyEvents are handled

    test "should fail on error" do
      event = %ReplyEvent{reply_to: self(), value: :error}

      metadata = %{}
      recorded_events = EventFactory.map_to_recorded_events([event], 1, metadata: metadata)
      state = setup_state(BatchHandler)

      {:stop, :bad_value, _state} = Handler.handle_info({:events, recorded_events}, state)
    end
  end

  describe "failure handling with error handler" do
    test "skip acknowledges the last event" do
      event1 = %ErrorEvent{reply_to: self(), strategy: "skip"}
      event2 = %ReplyEvent{reply_to: self(), value: 2}

      events = [event1, event2]

      metadata = %{}
      recorded_events = EventFactory.map_to_recorded_events(events, 1, metadata: metadata)
      last_recorded_event = List.last(recorded_events)
      state = setup_state(ErrorHandlingBatchHandler)

      Handler.handle_info({:events, recorded_events}, state)
      assert_received {:error, :skipping}
      assert_received {:batch, _, 2}
      assert_received {:acked, ^last_recorded_event}
    end

    test "should stop" do
      event1 = %ErrorEvent{reply_to: self(), strategy: "default"}
      event2 = %ReplyEvent{reply_to: self(), value: 2}
      events = [event1, event2]

      metadata = %{}
      recorded_events = EventFactory.map_to_recorded_events(events, 1, metadata: metadata)
      state = setup_state(ErrorHandlingBatchHandler)

      {:stop, _reason, _state} = Handler.handle_info({:events, recorded_events}, state)
    end

    test "should retry" do
      event1 = %ErrorEvent{reply_to: self(), strategy: "retry"}
      event2 = %ReplyEvent{reply_to: self(), value: 2}
      events = [event1, event2]

      metadata = %{}
      recorded_events = EventFactory.map_to_recorded_events(events, 1, metadata: metadata)
      state = setup_state(ErrorHandlingBatchHandler)

      {:stop, :too_many_failures, _state} = Handler.handle_info({:events, recorded_events}, state)
      assert_received {:error, :retry, %{failures: 1}}
      assert_received {:error, :retry, %{failures: 2}}
      assert_received {:error, :too_many_failures, %{failures: 3}}
    end
   end

  defp setup_state(handler_module) do
      Config.associate(self(), __MODULE__, [
            event_store: {MockAdapter, nil}
          ])

      %Handler{
        subscription: struct(Subscription,
          application: __MODULE__,
          subscription_pid: self()
        ),
        handler_callback: :batch,
        handler_module: handler_module,
        consistency: :eventual,
        last_seen_event: 0
      }

  end

  defmodule MockAdapter do
    def ack_event(nil, subscription_pid, event) do
      send subscription_pid, {:acked, event}
      :ok
    end
  end
end
