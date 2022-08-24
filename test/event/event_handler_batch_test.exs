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
    test "skip is not allowed" do
      event1 = %ReplyEvent{reply_to: self(), value: {:error, :skip}}
      event2 = %ReplyEvent{reply_to: self(), value: 2}
      events = [event1, event2]

      metadata = %{}
      recorded_events = EventFactory.map_to_recorded_events(events, 1, metadata: metadata)
      state = setup_state(ErrorHandlingBatchHandler)

      catch_throw Handler.handle_info({:events, recorded_events}, state)
    end

    test "should stop" do
      event1 = %ReplyEvent{reply_to: self(), value: {:error, :stop}}
      event2 = %ReplyEvent{reply_to: self(), value: 2}
      events = [event1, event2]

      metadata = %{}
      recorded_events = EventFactory.map_to_recorded_events(events, 1, metadata: metadata)
      state = setup_state(ErrorHandlingBatchHandler)

      {:stop, _reason, _state} = Handler.handle_info({:events, recorded_events}, state)
    end

    test "should retry" do
      event1 = %ReplyEvent{reply_to: self(), value: {:error, :retry}}
      event2 = %ReplyEvent{reply_to: self(), value: 2}
      events = [event1, event2]

      metadata = %{}
      recorded_events = EventFactory.map_to_recorded_events(events, 1, metadata: metadata)
      state = setup_state(ErrorHandlingBatchHandler)

      {:stop, :retry, _state} = Handler.handle_info({:events, recorded_events}, state)
      assert_received :seen_retry
      assert_received :seen_retry_call
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
