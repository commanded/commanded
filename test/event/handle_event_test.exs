defmodule Commanded.Event.HandleEventTest do
  use Commanded.MockEventStoreCase

  import Commanded.Enumerable, only: [pluck: 2]
  import Commanded.Assertions.EventAssertions

  alias Commanded.{DefaultApp, MockedApp}
  alias Commanded.Event.AppendingEventHandler
  alias Commanded.Event.EchoHandler
  alias Commanded.Event.Handler
  alias Commanded.Event.Mapper
  alias Commanded.Event.ReplyEvent
  alias Commanded.Event.UninterestingEvent
  alias Commanded.EventStore
  alias Commanded.EventStore.RecordedEvent
  alias Commanded.ExampleDomain.BankAccount.Events.BankAccountOpened
  alias Commanded.ExampleDomain.BankAccount.Events.MoneyDeposited
  alias Commanded.Helpers.EventFactory
  alias Commanded.Helpers.Wait
  alias Commanded.UUID

  describe "event handling" do
    setup do
      # start_supervised!(DefaultApp)
      handler = start_supervised!(EchoHandler)

      [handler: handler]
    end

    test "should handle received events", %{handler: handler} do
      event1 = %ReplyEvent{reply_to: reply_to(), value: 1}
      event2 = %ReplyEvent{reply_to: reply_to(), value: 2}
      events = [event1, event2]

      metadata = %{"key" => "value"}

      recorded_events = EventFactory.map_to_recorded_events(events, 1, metadata: metadata)

      send(handler, {:events, recorded_events})

      assert_receive {:event, ^handler, ^event1, metadata1}

      assert_enriched_metadata(metadata1, Enum.at(recorded_events, 0),
        additional_metadata: %{
          application: MockedApp,
          state: nil,
          handler_name: "Commanded.Event.EchoHandler"
        }
      )

      assert_receive {:event, ^handler, ^event2, metadata2}

      assert_enriched_metadata(metadata2, Enum.at(recorded_events, 1),
        additional_metadata: %{
          application: MockedApp,
          state: nil,
          handler_name: "Commanded.Event.EchoHandler"
        }
      )

      refute_receive {:event, _handler, _event, _metadata}
    end

    test "should ignore uninterested events", %{handler: handler} do
      interested_event1 = %ReplyEvent{reply_to: reply_to(), value: 1}
      interested_event2 = %ReplyEvent{reply_to: reply_to(), value: 2}

      # Include uninterested events within those the handler is interested in
      events = [
        %UninterestingEvent{},
        interested_event1,
        %UninterestingEvent{},
        interested_event2,
        %UninterestingEvent{}
      ]

      recorded_events = EventFactory.map_to_recorded_events(events)

      send(handler, {:events, recorded_events})

      # Receive only interested events
      assert_receive {:event, ^handler, ^interested_event1, _metadata1}
      assert_receive {:event, ^handler, ^interested_event2, _metadata2}

      refute_receive {:event, _handler, _event, _metadata}
    end

    test "should ignore unexpected messages", %{handler: handler} do
      import ExUnit.CaptureLog

      ref = Process.monitor(handler)

      send_unexpected_mesage = fn ->
        send(handler, :unexpected_message)

        refute_receive {:DOWN, ^ref, :process, ^handler, _}
      end

      assert capture_log(send_unexpected_mesage) =~
               "Commanded.Event.EchoHandler received unexpected message: :unexpected_message"
    end
  end

  describe "dynamic event handler" do
    setup do
      start_supervised!({MockedApp, name: :app1})
      start_supervised!({MockedApp, name: :app2})

      handler1 = start_supervised!({EchoHandler, application: :app1, name: "handler1"})
      handler2 = start_supervised!({EchoHandler, application: :app2, name: "handler2"})

      [handler1: handler1, handler2: handler2]
    end

    test "should handle received events", %{handler1: handler1, handler2: handler2} do
      event1 = %ReplyEvent{reply_to: reply_to(), value: 1}
      event2 = %ReplyEvent{reply_to: reply_to(), value: 2}

      metadata = %{"key" => "value"}

      recorded_events1 = EventFactory.map_to_recorded_events([event1], 1, metadata: metadata)
      recorded_events2 = EventFactory.map_to_recorded_events([event2], 1, metadata: metadata)

      send(handler1, {:events, recorded_events1})

      assert_receive {:event, ^handler1, ^event1, metadata1}
      refute_receive {:event, ^handler2, _event, _metadata}

      assert_enriched_metadata(metadata1, Enum.at(recorded_events1, 0),
        additional_metadata: %{
          application: :app1,
          state: nil,
          handler_name: "handler1"
        }
      )

      send(handler2, {:events, recorded_events2})

      assert_receive {:event, ^handler2, ^event2, metadata2}
      refute_receive {:event, ^handler1, _event, _metadata}

      assert_enriched_metadata(metadata2, Enum.at(recorded_events2, 0),
        additional_metadata: %{
          application: :app2,
          state: nil,
          handler_name: "handler2"
        }
      )

      refute_receive {:event, _handler, _event, _metadata}
    end
  end

  describe "appending handler" do
    setup do
      start_supervised!(DefaultApp)

      :ok
    end

    test "should ignore events created before the event handler's subscription when starting from `:current`" do
      stream_uuid = UUID.uuid4()
      initial_events = [%BankAccountOpened{account_number: "ACC123", initial_balance: 1_000}]
      new_events = [%MoneyDeposited{amount: 50, balance: 1_050}]

      :ok = EventStore.append_to_stream(DefaultApp, stream_uuid, 0, to_event_data(initial_events))

      wait_for_event(DefaultApp, BankAccountOpened)

      handler = start_supervised!({AppendingEventHandler, start_from: :current})

      %Handler{last_seen_event: last_seen_event} = :sys.get_state(handler)
      assert is_nil(last_seen_event)

      :ok = EventStore.append_to_stream(DefaultApp, stream_uuid, 1, to_event_data(new_events))

      wait_for_event(DefaultApp, MoneyDeposited, fn event, recorded_event ->
        event.amount == 50 and recorded_event.event_number == 2
      end)

      Wait.until(fn ->
        assert AppendingEventHandler.received_events() == new_events

        [metadata] = AppendingEventHandler.received_metadata()

        assert Map.get(metadata, :event_number) == 2
        assert Map.get(metadata, :stream_id) == stream_uuid
        assert Map.get(metadata, :stream_version) == 2
        assert %DateTime{} = Map.get(metadata, :created_at)

        %Handler{last_seen_event: last_seen_event} = :sys.get_state(handler)
        assert last_seen_event == 2
      end)
    end

    test "should receive events created before the event handler's subscription when starting from `:origin`" do
      stream_uuid = UUID.uuid4()
      initial_events = [%BankAccountOpened{account_number: "ACC123", initial_balance: 1_000}]
      new_events = [%MoneyDeposited{amount: 50, balance: 1_050}]

      :ok = EventStore.append_to_stream(DefaultApp, stream_uuid, 0, to_event_data(initial_events))

      start_supervised!({AppendingEventHandler, start_from: :origin})

      :ok = EventStore.append_to_stream(DefaultApp, stream_uuid, 1, to_event_data(new_events))

      wait_for_event(DefaultApp, MoneyDeposited)

      Wait.until(fn ->
        assert AppendingEventHandler.received_events() == initial_events ++ new_events

        received_metadata = AppendingEventHandler.received_metadata()

        assert pluck(received_metadata, :event_number) == [1, 2]
        assert pluck(received_metadata, :stream_version) == [1, 2]

        Enum.each(received_metadata, fn metadata ->
          assert Map.get(metadata, :stream_id) == stream_uuid
          assert %DateTime{} = Map.get(metadata, :created_at)
        end)
      end)
    end

    test "should ignore already seen events" do
      handler = start_supervised!({AppendingEventHandler, application: MockedApp})

      events = [
        %BankAccountOpened{account_number: "ACC123", initial_balance: 1_000},
        %MoneyDeposited{amount: 50, balance: 1_050}
      ]

      recorded_events = EventFactory.map_to_recorded_events(events)

      Wait.until(fn ->
        assert AppendingEventHandler.subscribed?()
      end)

      # send each event twice to simulate duplicate receives
      Enum.each(recorded_events, fn recorded_event ->
        send(handler, {:events, [recorded_event]})
        send(handler, {:events, [recorded_event]})
      end)

      Wait.until(fn ->
        assert AppendingEventHandler.received_events() == events
        assert pluck(AppendingEventHandler.received_metadata(), :stream_version) == [1, 2]
      end)
    end
  end

  defp assert_enriched_metadata(metadata, %RecordedEvent{} = event, opts) do
    enriched_metadata = RecordedEvent.enrich_metadata(event, opts)

    assert metadata == enriched_metadata
  end

  defp reply_to, do: :erlang.pid_to_list(self())

  defp to_event_data(events) do
    Mapper.map_to_event_data(events,
      causation_id: UUID.uuid4(),
      correlation_id: UUID.uuid4(),
      metadata: %{}
    )
  end
end
