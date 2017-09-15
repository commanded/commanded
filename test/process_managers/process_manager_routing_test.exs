defmodule Commanded.ProcessManager.ProcessManagerRoutingTest do
  use Commanded.StorageCase

  import Commanded.Assertions.EventAssertions

  alias Commanded.ExampleDomain.BankRouter
  alias Commanded.ExampleDomain.TransferMoneyProcessManager
  alias Commanded.ExampleDomain.BankAccount.Commands.OpenAccount
  alias Commanded.ExampleDomain.BankAccount.Events.{MoneyDeposited,MoneyWithdrawn}
  alias Commanded.ExampleDomain.MoneyTransfer.Commands.TransferMoney
  alias Commanded.ExampleDomain.MoneyTransfer.Events.MoneyTransferRequested

  @tag :wip
  test "should start a process manager in response to an event" do
    account_number1 = UUID.uuid4
    account_number2 = UUID.uuid4

    {:ok, _} = TransferMoneyProcessManager.start_link()

    # create two bank accounts
    :ok = BankRouter.dispatch(%OpenAccount{account_number: account_number1, initial_balance: 1_000})
    :ok = BankRouter.dispatch(%OpenAccount{account_number: account_number2, initial_balance:  500})

    # transfer funds between account 1 and account 2
    :ok = BankRouter.dispatch(%TransferMoney{
      transfer_uuid: UUID.uuid4,
      debit_account: account_number1,
      credit_account: account_number2,
      amount: 100,
    })

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
