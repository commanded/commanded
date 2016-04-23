defmodule Commanded.Event.HandleEventTest do
	use ExUnit.Case
	doctest Commanded.Event.Handler

  alias Commanded.Event.AppendingEventHandler
  alias Commanded.Entities.{Entity,Registry}
	alias Commanded.ExampleDomain.{BankAccount,AccountBalanceHandler}
	alias Commanded.ExampleDomain.BankAccount.Commands.{OpenAccount,DepositMoney}
	alias Commanded.ExampleDomain.BankAccount.Events.{BankAccountOpened,MoneyDeposited}
	alias Commanded.ExampleDomain.{OpenAccountHandler,DepositMoneyHandler}
  alias Commanded.Helpers.Wait

	setup do
		EventStore.Storage.reset!
		{:ok, _} = Commanded.Supervisor.start_link
		:ok
	end

	test "should be notified of events" do
    {:ok, _} = AccountBalanceHandler.start_link
		{:ok, handler} = Commanded.Event.Handler.start_link("account_balance", AccountBalanceHandler)

    events = [
      %BankAccountOpened{account_number: "ACC123", initial_balance: 1_000},
      %MoneyDeposited{amount: 50, balance: 1_050}
    ]
    recorded_events = map_to_recorded_events(events)

    send(handler, {:events, recorded_events})

    Wait.until fn ->
      assert AccountBalanceHandler.current_balance == 1_050
    end
	end

	test "should ignore already seen events" do
    {:ok, _} = AppendingEventHandler.start_link
    {:ok, handler} = Commanded.Event.Handler.start_link("test_event_handler", AppendingEventHandler)

    events = [
      %BankAccountOpened{account_number: "ACC123", initial_balance: 1_000},
      %MoneyDeposited{amount: 50, balance: 1_050}
    ]
    recorded_events = map_to_recorded_events(events)

    send(handler, {:events, recorded_events})
    send(handler, {:events, recorded_events})

    Wait.until fn ->
      assert AppendingEventHandler.received_events == events
    end
	end

  #test "should ignore uninterested events"

  defp map_to_recorded_events(events) do
    events
    |> Commanded.Event.Serializer.map_to_event_data(UUID.uuid4)
    |> Enum.with_index(1)
    |> Enum.map(fn {event, index} ->
      %EventStore.RecordedEvent{
        event_id: index,
        stream_id: 1,
        stream_version: index,
        correlation_id: event.correlation_id,
        event_type: event.event_type,
        headers: event.headers,
        payload: event.payload,
        created_at: :calendar.universal_time
      }
    end)
  end
end
