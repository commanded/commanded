defmodule Commanded.ProcessManager.ProcessManagerRoutingTest do
  use ExUnit.Case
  doctest Commanded.ProcessManagers.Router

  alias Commanded.ProcessManagers.Router
  alias Commanded.ExampleDomain.TransferMoneyProcessManager
  alias Commanded.ExampleDomain.{BankAccount,OpenAccountHandler}
  alias Commanded.ExampleDomain.BankAccount.Commands.OpenAccount
  alias Commanded.ExampleDomain.{MoneyTransfer,TransferMoneyHandler}
  alias Commanded.ExampleDomain.MoneyTransfer.Commands.TransferMoney
  alias Commanded.Commands.{Dispatcher,Registry}
  alias Commanded.Helpers

  setup do
    EventStore.Storage.reset!
    Commanded.Supervisor.start_link
    :ok = Registry.register(OpenAccount, OpenAccountHandler)
    :ok = Registry.register(TransferMoney, TransferMoneyHandler)
    :ok
  end

  @tag :wip
  test "start a process manager in response to an event" do
    account1_uuid = UUID.uuid4
    account2_uuid = UUID.uuid4

    {:ok, _} = Router.start_link("transfer_money_process_manager", TransferMoneyProcessManager)

    # create two bank accounts
    :ok = Dispatcher.dispatch(%OpenAccount{aggregate_uuid: account1_uuid, account_number: "ACC123", initial_balance: 1_000})
    :ok = Dispatcher.dispatch(%OpenAccount{aggregate_uuid: account2_uuid, account_number: "ACC456", initial_balance:  500})

    # transfer funds between account 1 and account 2
    :ok = Dispatcher.dispatch(%TransferMoney{source_account: account1_uuid, target_account: account2_uuid, amount: 100})

    # :timer.sleep(1_000)

    # should withdraw from ACC123
    # should deposit into account ACC456
  end
end
