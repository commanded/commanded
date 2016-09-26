defmodule Commanded.Entities.ExecuteCommandForAggregateTest do
  use ExUnit.Case
  doctest Commanded.Aggregates.Aggregate

  alias Commanded.Aggregates.{Registry,Aggregate}
  alias Commanded.ExampleDomain.{BankAccount,OpenAccountHandler,DepositMoneyHandler}
  alias Commanded.ExampleDomain.BankAccount.Commands.{OpenAccount,DepositMoney}
  alias Commanded.ExampleDomain.BankAccount.Events.BankAccountOpened
  alias Commanded.Extensions

  setup do
    EventStore.Storage.reset!
    Commanded.Supervisor.start_link
    :ok
  end

  test "should execute command against an aggregate" do
    account_number = UUID.uuid4

    {:ok, aggregate} = Registry.open_aggregate(BankAccount, account_number)

    :ok = Aggregate.execute(aggregate, %OpenAccount{account_number: account_number, initial_balance: 1_000}, OpenAccountHandler)

    Extensions.Process.shutdown(aggregate)

    # reload aggregate to fetch persisted events from event store and rebuild state by applying saved events
    {:ok, aggregate} = Registry.open_aggregate(BankAccount, account_number)

    bank_account = Aggregate.aggregate_state(aggregate)

    assert bank_account.state.account_number == account_number
    assert bank_account.state.balance == 1_000
    assert length(bank_account.pending_events) == 0
    assert bank_account.uuid == account_number
    assert bank_account.version == 1
  end

  test "should execute command against an aggregate with concurrency error should reload events and retry command" do
    account_number = UUID.uuid4

    {:ok, aggregate} = Registry.open_aggregate(BankAccount, account_number)

    {:ok, stream} = EventStore.Streams.open_stream(account_number)

    # write an event to the aggregate's stream, bypassing the aggregate process (simulate concurrency error)
    EventStore.Streams.Stream.append_to_stream(stream, 0, [
      %EventStore.EventData{
        event_type: "Elixir.Commanded.ExampleDomain.BankAccount.Events.BankAccountOpened",
        data: %BankAccountOpened{account_number: account_number, initial_balance: 1_000}
      }
    ])

    Aggregate.execute(aggregate, %DepositMoney{account_number: account_number, transfer_uuid: UUID.uuid4, amount: 50}, DepositMoneyHandler)

    bank_account = Aggregate.aggregate_state(aggregate)

    assert bank_account.state.account_number == account_number
    assert bank_account.state.balance == 1_050
  end

  test "aggregate returning an error tuple should not persist pending events or state" do
    account_number = UUID.uuid4

    {:ok, aggregate} = Registry.open_aggregate(BankAccount, account_number)

    :ok = Aggregate.execute(aggregate, %OpenAccount{account_number: account_number, initial_balance: 1_000}, OpenAccountHandler)

    state_before = Aggregate.aggregate_state(aggregate)

    # attempt to open same account should fail with a descriptive error
    {:error, :account_already_open} = Aggregate.execute(aggregate, %OpenAccount{account_number: account_number, initial_balance: 1}, OpenAccountHandler)

    state_after = Aggregate.aggregate_state(aggregate)

    assert state_before == state_after
  end

  @tag :skip
  test "should persist pending events in order applied"
end
