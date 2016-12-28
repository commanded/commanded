defmodule Commanded.Entities.ExecuteCommandForAggregateTest do
  use Commanded.StorageCase
  use Commanded.EventStore

  doctest Commanded.Aggregates.Aggregate

  alias Commanded.Aggregates.{Registry,Aggregate}
  alias Commanded.ExampleDomain.{BankAccount,OpenAccountHandler,DepositMoneyHandler}
  alias Commanded.ExampleDomain.BankAccount.Commands.{OpenAccount,DepositMoney}
  alias Commanded.ExampleDomain.BankAccount.Events.BankAccountOpened
  alias Commanded.Helpers

  test "execute command against an aggregate" do
    account_number = UUID.uuid4

    {:ok, aggregate} = Registry.open_aggregate(BankAccount, account_number)

    :ok = Aggregate.execute(aggregate, %OpenAccount{account_number: account_number, initial_balance: 1_000}, BankAccount, :open_account)

    Helpers.Process.shutdown(aggregate)

    # reload aggregate to fetch persisted events from event store and rebuild state by applying saved events
    {:ok, aggregate} = Registry.open_aggregate(BankAccount, account_number)

    assert Aggregate.aggregate_uuid(aggregate) == account_number
    assert Aggregate.aggregate_version(aggregate) == 1
    assert Aggregate.aggregate_state(aggregate) == %BankAccount{account_number: account_number, balance: 1_000, state: :active}
  end

  test "execute command via a command handler" do
    account_number = UUID.uuid4

    {:ok, aggregate} = Registry.open_aggregate(BankAccount, account_number)

    :ok = Aggregate.execute(aggregate, %OpenAccount{account_number: account_number, initial_balance: 1_000}, OpenAccountHandler, :handle)

    Helpers.Process.shutdown(aggregate)

    # reload aggregate to fetch persisted events from event store and rebuild state by applying saved events
    {:ok, aggregate} = Registry.open_aggregate(BankAccount, account_number)

    assert Aggregate.aggregate_uuid(aggregate) == account_number
    assert Aggregate.aggregate_version(aggregate) == 1
    assert Aggregate.aggregate_state(aggregate) == %BankAccount{account_number: account_number, balance: 1_000, state: :active}
  end

  test "aggregate raising an exception should not persist pending events or state" do
    account_number = UUID.uuid4

    {:ok, aggregate} = Registry.open_aggregate(BankAccount, account_number)

    :ok = Aggregate.execute(aggregate, %OpenAccount{account_number: account_number, initial_balance: 1_000}, OpenAccountHandler, :handle)

    state_before = Aggregate.aggregate_state(aggregate)

    assert_process_exit(aggregate, fn ->
      Aggregate.execute(aggregate, %OpenAccount{account_number: account_number, initial_balance: 1}, OpenAccountHandler, :handle)
    end)

    {:ok, aggregate} = Registry.open_aggregate(BankAccount, account_number)
    assert state_before == Aggregate.aggregate_state(aggregate)
  end

  test "executing a command against an aggregate with concurrency error should terminate aggregate process" do
    account_number = UUID.uuid4

    {:ok, aggregate} = Registry.open_aggregate(BankAccount, account_number)
    stream = account_number

    # block until aggregate has loaded its initial (empty) state
    Aggregate.aggregate_state(aggregate)

    # write an event to the aggregate's stream, bypassing the aggregate process (simulate concurrency error)
    :ok = @event_store.append_to_stream(stream, 0, [
      %Commanded.EventStore.EventData{
        event_type: "Elixir.Commanded.ExampleDomain.BankAccount.Events.BankAccountOpened",
        data: %BankAccountOpened{account_number: account_number, initial_balance: 1_000}
      }
    ])

    assert_process_exit(aggregate, fn ->
      Aggregate.execute(aggregate, %DepositMoney{account_number: account_number, transfer_uuid: UUID.uuid4, amount: 50}, DepositMoneyHandler, :handle)
    end)
  end

  def assert_process_exit(process, fun) do
    Process.flag(:trap_exit, true)

    spawn_link(fun)

    # process should exit
    assert_receive({:EXIT, _from, _reason})
    assert Process.alive?(process) == false
  end
end
