defmodule Commanded.Event.HandleEventTest do
  use Commanded.StorageCase

  import Commanded.Enumerable, only: [pluck: 2]
  import Commanded.Assertions.EventAssertions

  alias Commanded.EventStore
  alias Commanded.Event.{AppendingEventHandler,UninterestingEvent}
  alias Commanded.Helpers.EventFactory
  alias Commanded.Helpers.{ProcessHelper,Wait}
  alias Commanded.ExampleDomain.BankAccount.AccountBalanceHandler
  alias Commanded.ExampleDomain.BankAccount.Events.{BankAccountOpened,MoneyDeposited}

  setup do
    on_exit fn ->
      ProcessHelper.shutdown(AccountBalanceHandler)
      ProcessHelper.shutdown(AppendingEventHandler)
    end
  end

  test "should be notified of events" do
    {:ok, handler} = AccountBalanceHandler.start_link()

    events = [
      %BankAccountOpened{account_number: "ACC123", initial_balance: 1_000},
      %MoneyDeposited{amount: 50, balance: 1_050}
    ]
    recorded_events = EventFactory.map_to_recorded_events(events)

    send(handler, {:events, recorded_events})

    Wait.until(fn ->
      assert AccountBalanceHandler.current_balance == 1_050
    end)
  end

  test "should ignore uninterested events" do
    {:ok, handler} = AccountBalanceHandler.start_link()

    # include uninterested events within those the handler is interested in
    events = [
      %UninterestingEvent{},
      %BankAccountOpened{account_number: "ACC123", initial_balance: 1_000},
      %UninterestingEvent{},
      %MoneyDeposited{amount: 50, balance: 1_050},
      %UninterestingEvent{}
    ]
    recorded_events = EventFactory.map_to_recorded_events(events)

    send(handler, {:events, recorded_events})

    Wait.until(fn ->
      assert AccountBalanceHandler.current_balance == 1_050
    end)
  end

  test "should ignore events created before the event handler's subscription when starting from `:current`" do
    stream_uuid = UUID.uuid4
    initial_events = [%BankAccountOpened{account_number: "ACC123", initial_balance: 1_000}]
    new_events = [%MoneyDeposited{amount: 50, balance: 1_050}]

    {:ok, 1} = EventStore.append_to_stream(stream_uuid, 0, Commanded.Event.Mapper.map_to_event_data(initial_events, UUID.uuid4(), UUID.uuid4(), %{}))

    wait_for_event BankAccountOpened

    {:ok, _handler} = AppendingEventHandler.start_link(start_from: :current)

    {:ok, 2} = EventStore.append_to_stream(stream_uuid, 1, Commanded.Event.Mapper.map_to_event_data(new_events, UUID.uuid4(), UUID.uuid4(), %{}))

    wait_for_event MoneyDeposited

    Wait.until(fn ->
      assert AppendingEventHandler.received_events() == new_events

      [ metadata ] = AppendingEventHandler.received_metadata()

      assert Map.get(metadata, :event_number) == 2
      assert Map.get(metadata, :stream_id) == stream_uuid
      assert Map.get(metadata, :stream_version) == 2
      assert %NaiveDateTime{} = Map.get(metadata, :created_at)
    end)
	end

  test "should receive events created before the event handler's subscription when starting from `:origin`" do
    stream_uuid = UUID.uuid4
    initial_events = [%BankAccountOpened{account_number: "ACC123", initial_balance: 1_000}]
    new_events = [%MoneyDeposited{amount: 50, balance: 1_050}]

    {:ok, 1} = EventStore.append_to_stream(stream_uuid, 0, Commanded.Event.Mapper.map_to_event_data(initial_events, UUID.uuid4(), UUID.uuid4(), %{}))

    {:ok, _handler} = AppendingEventHandler.start_link(start_from: :origin)

    {:ok, 2} = EventStore.append_to_stream(stream_uuid, 1, Commanded.Event.Mapper.map_to_event_data(new_events, UUID.uuid4(), UUID.uuid4(), %{}))

    wait_for_event MoneyDeposited

    Wait.until(fn ->
      assert AppendingEventHandler.received_events() == initial_events ++ new_events

      received_metadata = AppendingEventHandler.received_metadata()

      assert pluck(received_metadata, :event_number) == [1, 2]
      assert pluck(received_metadata, :stream_version) == [1, 2]

      Enum.each(received_metadata, fn metadata ->
        assert Map.get(metadata, :stream_id) == stream_uuid
        assert %NaiveDateTime{} = Map.get(metadata, :created_at)
      end)
    end)
	end

	test "should ignore already seen events" do
    {:ok, handler} = AppendingEventHandler.start_link()

    events = [
      %BankAccountOpened{account_number: "ACC123", initial_balance: 1_000},
      %MoneyDeposited{amount: 50, balance: 1_050}
    ]
    recorded_events = EventFactory.map_to_recorded_events(events)

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
