defmodule Commanded.Event.HandleBatchTest do
  use ExUnit.Case

  import Commanded.Enumerable, only: [pluck: 2]
  import Commanded.Assertions.EventAssertions

  alias Commanded.DefaultApp
  alias Commanded.Event.AppendingEventHandler
  alias Commanded.Event.BatchHandler
  alias Commanded.Event.Handler
  alias Commanded.Event.ReplyEvent
  alias Commanded.Event.UninterestingEvent
  alias Commanded.EventStore
  alias Commanded.EventStore.RecordedEvent
  alias Commanded.ExampleDomain.BankAccount.Events.BankAccountOpened
  alias Commanded.ExampleDomain.BankAccount.Events.MoneyDeposited
  alias Commanded.Helpers.EventFactory
  alias Commanded.Helpers.Wait

  describe "batch handling" do
    setup do
      start_supervised!(DefaultApp)
      handler = start_supervised!(BatchHandler)

      [handler: handler]
    end

    test "should receive events in batches", %{handler: handler} do
      event1 = %ReplyEvent{reply_to: self(), value: 1}
      event2 = %ReplyEvent{reply_to: self(), value: 2}
      events = [event1, event2]

      metadata = %{"key" => "value"}

      recorded_events = EventFactory.map_to_recorded_events(events, 1, metadata: metadata)

      send(handler, {:events, recorded_events})

      assert_receive {:batch, ^handler, ^events, metadata1}
    end
  end
end
