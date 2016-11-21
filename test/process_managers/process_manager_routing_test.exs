defmodule Commanded.ProcessManager.ProcessManagerRoutingTest do
  use Commanded.StorageCase
  doctest Commanded.ProcessManagers.ProcessRouter

  alias Commanded.ProcessManagers.ProcessRouter
  alias Commanded.ExampleDomain.TransferMoneyProcessManager
  alias Commanded.ExampleDomain.{OpenAccountHandler,DepositMoneyHandler,TransferMoneyHandler,WithdrawMoneyHandler}
  alias Commanded.ExampleDomain.{BankAccount,MoneyTransfer}
  alias Commanded.ExampleDomain.BankAccount.Commands.{OpenAccount,DepositMoney,WithdrawMoney}
  alias Commanded.ExampleDomain.BankAccount.Events.{MoneyDeposited,MoneyWithdrawn}
  alias Commanded.ExampleDomain.MoneyTransfer.Commands.{TransferMoney}
  alias Commanded.ExampleDomain.MoneyTransfer.Events.{MoneyTransferRequested}

  import Commanded.Assertions.EventAssertions

  defmodule BankRouter do
    use Commanded.Commands.Router

    dispatch OpenAccount, to: OpenAccountHandler, aggregate: BankAccount, identity: :account_number
    dispatch DepositMoney, to: DepositMoneyHandler, aggregate: BankAccount, identity: :account_number
    dispatch WithdrawMoney, to: WithdrawMoneyHandler, aggregate: BankAccount, identity: :account_number
    dispatch TransferMoney, to: TransferMoneyHandler, aggregate: MoneyTransfer, identity: :transfer_uuid
  end

  test "should start a process manager in response to an event" do
    account_number1 = UUID.uuid4
    account_number2 = UUID.uuid4

    {:ok, _} = ProcessRouter.start_link("transfer_money_process_manager", TransferMoneyProcessManager, BankRouter)

    # create two bank accounts
    :ok = BankRouter.dispatch(%OpenAccount{account_number: account_number1, initial_balance: 1_000})
    :ok = BankRouter.dispatch(%OpenAccount{account_number: account_number2, initial_balance:  500})

    # transfer funds between account 1 and account 2
    :ok = BankRouter.dispatch(%TransferMoney{transfer_uuid: UUID.uuid4, debit_account: account_number1, credit_account: account_number2, amount: 100})

    assert_receive_event MoneyTransferRequested, fn event ->
      assert event.debit_account == account_number1
      assert event.credit_account == account_number2
      assert event.amount == 100
    end

    assert_receive_event MoneyWithdrawn, fn event ->
      assert event.account_number == account_number1
      assert event.amount == 100
      assert event.balance == 900
    end

    assert_receive_event MoneyDeposited, fn event ->
      assert event.account_number == account_number2
      assert event.amount == 100
      assert event.balance == 600
    end
  end
end
