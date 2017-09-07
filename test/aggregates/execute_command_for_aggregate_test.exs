defmodule Commanded.Entities.ExecuteCommandForAggregateTest do
  use Commanded.StorageCase

  alias Commanded.Aggregates.Aggregate
  alias Commanded.EventStore
  alias Commanded.ExampleDomain.{BankAccount,OpenAccountHandler,DepositMoneyHandler}
  alias Commanded.ExampleDomain.BankAccount.Commands.{OpenAccount,DepositMoney}
  alias Commanded.ExampleDomain.BankAccount.Events.BankAccountOpened
  alias Commanded.Helpers

  @registry_provider Application.get_env(:commanded, :registry_provider, Registry)

  test "execute command against an aggregate" do
    account_number = UUID.uuid4

    {:ok, ^account_number} = Commanded.Aggregates.Supervisor.open_aggregate(BankAccount, account_number)

    {:ok, 1} = Aggregate.execute(account_number, %OpenAccount{account_number: account_number, initial_balance: 1_000}, BankAccount, :open_account)

    Helpers.Process.shutdown(account_number)

    # reload aggregate to fetch persisted events from event store and rebuild state by applying saved events
    {:ok, ^account_number} = Commanded.Aggregates.Supervisor.open_aggregate(BankAccount, account_number)

    assert Aggregate.aggregate_version(account_number) == 1
    assert Aggregate.aggregate_state(account_number) == %BankAccount{account_number: account_number, balance: 1_000, state: :active}
  end

  test "execute command via a command handler" do
    account_number = UUID.uuid4

    {:ok, ^account_number} = Commanded.Aggregates.Supervisor.open_aggregate(BankAccount, account_number)

    {:ok, 1} = Aggregate.execute(account_number, %OpenAccount{account_number: account_number, initial_balance: 1_000}, OpenAccountHandler, :handle)

    Helpers.Process.shutdown(account_number)

    # reload aggregate to fetch persisted events from event store and rebuild state by applying saved events
    {:ok, ^account_number} = Commanded.Aggregates.Supervisor.open_aggregate(BankAccount, account_number)

    assert Aggregate.aggregate_version(account_number) == 1
    assert Aggregate.aggregate_state(account_number) == %BankAccount{account_number: account_number, balance: 1_000, state: :active}
  end

  test "aggregate raising an exception should not persist pending events or state" do
    account_number = UUID.uuid4

    {:ok, ^account_number} = Commanded.Aggregates.Supervisor.open_aggregate(BankAccount, account_number)

    {:ok, 1} = Aggregate.execute(account_number, %OpenAccount{account_number: account_number, initial_balance: 1_000}, OpenAccountHandler, :handle)

    state_before = Aggregate.aggregate_state(account_number)

    assert_process_exit(account_number, fn ->
      Aggregate.execute(account_number, %OpenAccount{account_number: account_number, initial_balance: 1}, OpenAccountHandler, :handle)
    end)

    {:ok, ^account_number} = Commanded.Aggregates.Supervisor.open_aggregate(BankAccount, account_number)
    assert state_before == Aggregate.aggregate_state(account_number)
  end

  test "executing a command against an aggregate with concurrency error should terminate aggregate process" do
    account_number = UUID.uuid4

    {:ok, ^account_number} = Commanded.Aggregates.Supervisor.open_aggregate(BankAccount, account_number)

    # block until aggregate has loaded its initial (empty) state
    Aggregate.aggregate_state(account_number)

    # write an event to the aggregate's stream, bypassing the aggregate process (simulate concurrency error)
    {:ok, _} = EventStore.append_to_stream(account_number, 0, [
      %Commanded.EventStore.EventData{
        event_type: "Elixir.Commanded.ExampleDomain.BankAccount.Events.BankAccountOpened",
        data: %BankAccountOpened{account_number: account_number, initial_balance: 1_000}
      }
    ])

    assert_process_exit(account_number, fn ->
      Aggregate.execute(account_number, %DepositMoney{account_number: account_number, transfer_uuid: UUID.uuid4, amount: 50}, DepositMoneyHandler, :handle)
    end)
  end

  def assert_process_exit(aggregate_uuid, fun) do
    Process.flag(:trap_exit, true)

    spawn_link(fun)

    # process should exit
    assert_receive({:EXIT, _from, _reason})
    assert apply(@registry_provider, :whereis_name, [{:aggregate_registry, aggregate_uuid}]) == :undefined
  end
end
