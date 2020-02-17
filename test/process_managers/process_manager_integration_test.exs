defmodule Commanded.ProcessManagers.ProcessManagerIntegrationTest do
  use ExUnit.Case

  import Commanded.Assertions.EventAssertions

  alias Commanded.ExampleDomain.BankApp
  alias Commanded.ExampleDomain.BankRouter
  alias Commanded.ExampleDomain.TransferMoneyProcessManager
  alias Commanded.ExampleDomain.BankAccount.Commands.OpenAccount
  alias Commanded.ExampleDomain.BankAccount.Events.MoneyDeposited
  alias Commanded.ExampleDomain.BankAccount.Events.MoneyWithdrawn
  alias Commanded.ExampleDomain.MoneyTransfer.Commands.TransferMoney
  alias Commanded.ExampleDomain.MoneyTransfer.Events.MoneyTransferRequested
  alias Commanded.Helpers.CommandAuditMiddleware
  alias Commanded.ProcessManagers.ProcessRouter

  setup do
    start_supervised!(CommandAuditMiddleware)
    start_supervised!(BankApp)

    :ok
  end

  test "should start a process manager in response to an event" do
    account_number1 = UUID.uuid4()
    account_number2 = UUID.uuid4()
    transfer_uuid = UUID.uuid4()

    process_router = start_supervised!(TransferMoneyProcessManager)

    # Create two bank accounts
    :ok = open_account(account_number1, 1_000)
    :ok = open_account(account_number2, 500)

    # Transfer funds between account 1 and account 2
    :ok = transfer_funds(transfer_uuid, account_number1, account_number2, 100)

    assert_receive_event(BankApp, MoneyTransferRequested, fn event ->
      assert event.debit_account == account_number1
      assert event.credit_account == account_number2
      assert event.amount == 100
    end)

    assert_receive_event(BankApp, MoneyWithdrawn, fn event ->
      assert event.account_number == account_number1
      assert event.amount == 100
      assert event.balance == 900
    end)

    assert_receive_event(BankApp, MoneyDeposited, fn event ->
      assert event.account_number == account_number2
      assert event.amount == 100
      assert event.balance == 600
    end)

    assert [{^transfer_uuid, _}] = ProcessRouter.process_instances(process_router)
  end

  defp open_account(account_number, initial_balance) do
    command = %OpenAccount{account_number: account_number, initial_balance: initial_balance}

    BankRouter.dispatch(command, application: BankApp)
  end

  defp transfer_funds(transfer_uuid, from_account_number, to_account_number2, amount) do
    command = %TransferMoney{
      transfer_uuid: transfer_uuid,
      debit_account: from_account_number,
      credit_account: to_account_number2,
      amount: amount
    }

    BankRouter.dispatch(command, application: BankApp)
  end
end
