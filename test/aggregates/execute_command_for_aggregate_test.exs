defmodule Commanded.Entities.ExecuteCommandForAggregateTest do
  use ExUnit.Case
  doctest Commanded.Aggregates.Aggregate

  alias Commanded.Aggregates.{Registry,Aggregate}
  alias Commanded.ExampleDomain.{BankAccount,OpenAccountHandler,DepositMoneyHandler}
  alias Commanded.ExampleDomain.BankAccount.Commands.{OpenAccount,DepositMoney}
  alias Commanded.Helpers

  setup do
    {:ok, _} = Registry.start_link
    :ok
  end

  test "execute command against an aggregate" do
    aggregate_uuid = UUID.uuid4

    {:ok, aggregate} = Registry.open_aggregate(BankAccount, aggregate_uuid)

    :ok = Aggregate.execute(aggregate, %OpenAccount{account_number: "ACC123", initial_balance: 1_000}, OpenAccountHandler)

    Helpers.Process.shutdown(aggregate)

    # reload aggregate to fetch persisted events from event store and rebuild state by applying saved events
    {:ok, aggregate} = Registry.open_aggregate(BankAccount, aggregate_uuid)

    bank_account = Aggregate.state(aggregate)

    assert bank_account.state.account_number == "ACC123"
    assert bank_account.state.balance == 1_000
    assert length(bank_account.pending_events) == 0
    assert bank_account.uuid == aggregate_uuid
    assert bank_account.version == 1
  end

  test "execute command against an aggregate with concurrency error should reload events and retry command" do
    aggregate_uuid = UUID.uuid4

    {:ok, aggregate} = Registry.open_aggregate(BankAccount, aggregate_uuid)

    # write an event to the aggregate's stream, bypassing the aggregate process (simulate concurrency error)
    EventStore.append_to_stream(aggregate_uuid, 0, [
      %EventStore.EventData{
        event_type: "Elixir.Commanded.ExampleDomain.BankAccount.Events.BankAccountOpened",
        headers: nil,
        payload: "{\"initial_balance\":1000,\"account_number\":\"ACC123\"}"
      }
    ])

    Aggregate.execute(aggregate, %DepositMoney{aggregate_uuid: aggregate_uuid, transfer_uuid: UUID.uuid4, amount: 50}, DepositMoneyHandler)

    bank_account = Aggregate.state(aggregate)

    assert bank_account.state.account_number == "ACC123"
    assert bank_account.state.balance == 1_050
  end
end
