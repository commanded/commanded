defmodule Commanded.Event.HandleEventTest do
  use Commanded.StorageCase

  import Commanded.Enumerable, only: [pluck: 2]
  import Commanded.Assertions.EventAssertions

  alias Commanded.EventStore
  alias Commanded.Event.AppendingEventHandler
  alias Commanded.Helpers.EventFactory
  alias Commanded.Helpers.Wait
  alias Commanded.ExampleDomain.AccountBalanceHandler
  alias Commanded.ExampleDomain.BankAccount.Events.{BankAccountOpened,MoneyDeposited}

  test "should be notified of events" do
    {:ok, _} = AccountBalanceHandler.start_link()
    {:ok, handler} = Commanded.Event.Handler.start_link("account_balance", AccountBalanceHandler)

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

  defmodule UninterestingEvent, do: defstruct [field: nil]

  test "should ignore uninterested events" do
    {:ok, _} = AccountBalanceHandler.start_link
		{:ok, handler} = Commanded.Event.Handler.start_link("account_balance", AccountBalanceHandler)

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

  test "should ignore events created before the event handler's subscription when starting from `current`" do
    {:ok, _} = AppendingEventHandler.start_link()

    stream_uuid = UUID.uuid4
    initial_events = [%BankAccountOpened{account_number: "ACC123", initial_balance: 1_000}]
    new_events = [%MoneyDeposited{amount: 50, balance: 1_050}]

    {:ok, 1} = EventStore.append_to_stream(stream_uuid, 0, Commanded.Event.Mapper.map_to_event_data(initial_events, UUID.uuid4))

    wait_for_event BankAccountOpened

    {:ok, _handler} = Commanded.Event.Handler.start_link("test_event_handler", AppendingEventHandler, start_from: :current)

    {:ok, 2} = EventStore.append_to_stream(stream_uuid, 1, Commanded.Event.Mapper.map_to_event_data(new_events, UUID.uuid4))

    wait_for_event MoneyDeposited

    Wait.until(fn ->
      assert AppendingEventHandler.received_events == new_events
      assert pluck(AppendingEventHandler.received_metadata, :stream_version) == [2]
    end)
	end

  test "should receive events created before the event handler's subscription when starting from `origin`" do
    {:ok, _} = AppendingEventHandler.start_link()

    stream_uuid = UUID.uuid4
    initial_events = [%BankAccountOpened{account_number: "ACC123", initial_balance: 1_000}]
    new_events = [%MoneyDeposited{amount: 50, balance: 1_050}]

    {:ok, 1} = EventStore.append_to_stream(stream_uuid, 0, Commanded.Event.Mapper.map_to_event_data(initial_events, UUID.uuid4))

    {:ok, _handler} = Commanded.Event.Handler.start_link("test_event_handler", AppendingEventHandler, start_from: :origin)

    {:ok, 2} = EventStore.append_to_stream(stream_uuid, 1, Commanded.Event.Mapper.map_to_event_data(new_events, UUID.uuid4))

    wait_for_event MoneyDeposited

    Wait.until(fn ->
      assert AppendingEventHandler.received_events == initial_events ++ new_events
      assert pluck(AppendingEventHandler.received_metadata, :stream_version) == [1, 2]
    end)
	end

	test "should ignore already seen events" do
    {:ok, _} = AppendingEventHandler.start_link
    {:ok, handler} = Commanded.Event.Handler.start_link("test_event_handler", AppendingEventHandler)

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
      assert AppendingEventHandler.received_events == events
      assert pluck(AppendingEventHandler.received_metadata, :stream_version) == [1, 2]
    end)
	end
end
