defmodule Commanded.Event.HandleBatchTest do
  use ExUnit.Case, async: true

  alias Commanded.Application.Config
  alias Commanded.Event.Handler
  alias Commanded.EventStore.Subscription

  # Test support code
  alias Commanded.Helpers.EventFactory
  alias Commanded.Event.BatchHandler
  alias Commanded.Event.ReplyEvent

  describe "batch handling" do
    test "should receive events in batches" do
      event1 = %ReplyEvent{reply_to: self(), value: 1}
      event2 = %ReplyEvent{reply_to: self(), value: 2}
      events = [event1, event2]

      metadata = %{"key" => "value"}

      recorded_events = EventFactory.map_to_recorded_events(events, 1, metadata: metadata)

      Config.associate(self(), __MODULE__, [
            event_store: {MockAdapter, nil}
          ])

      state = %Handler{
        subscription: struct(Subscription,
          application: __MODULE__,
          subscription_pid: self()
        ),
        handler_callback: :batch,
        handler_module: BatchHandler,
        consistency: :eventual
      }

      {:noreply, state} = Handler.handle_info({:events, recorded_events}, state)
      assert %Handler{

      } = state
    end
  end
end

# TODO Batching: give this a nice home
defmodule MockAdapter do

  def ack_event(nil, subscription_pid, event) do
    send subscription_pid, {:acked, event}
    :ok
  end

end
