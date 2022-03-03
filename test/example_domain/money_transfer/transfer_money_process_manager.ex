defmodule Commanded.ExampleDomain.TransferMoneyProcessManager do
  @moduledoc false

  use Commanded.ProcessManagers.ProcessManager,
    application: Commanded.ExampleDomain.BankApp,
    name: __MODULE__

  alias Commanded.ExampleDomain.BankAccount.Commands.{DepositMoney, WithdrawMoney}
  alias Commanded.ExampleDomain.BankAccount.Events.{MoneyDeposited, MoneyWithdrawn}
  alias Commanded.ExampleDomain.MoneyTransfer.Events.MoneyTransferRequested
  alias Commanded.ExampleDomain.TransferMoneyProcessManager

  @derive Jason.Encoder
  defstruct [:transfer_uuid, :debit_account, :credit_account, :amount, :status]

  def interested?(%MoneyTransferRequested{transfer_uuid: transfer_uuid}),
    do: {:start, transfer_uuid}

  def interested?(%MoneyWithdrawn{transfer_uuid: transfer_uuid}),
    do: {:continue, transfer_uuid}

  def interested?(%MoneyDeposited{transfer_uuid: transfer_uuid}),
    do: {:continue, transfer_uuid}

  def handle(%TransferMoneyProcessManager{}, %MoneyTransferRequested{} = event) do
    %MoneyTransferRequested{
      transfer_uuid: transfer_uuid,
      debit_account: debit_account,
      amount: amount
    } = event

    %WithdrawMoney{account_number: debit_account, transfer_uuid: transfer_uuid, amount: amount}
  end

  def handle(%TransferMoneyProcessManager{} = pm, %MoneyWithdrawn{}) do
    %TransferMoneyProcessManager{
      transfer_uuid: transfer_uuid,
      credit_account: credit_account,
      amount: amount
    } = pm

    %DepositMoney{account_number: credit_account, transfer_uuid: transfer_uuid, amount: amount}
  end

  ## State mutators

  def apply(%TransferMoneyProcessManager{} = transfer, %MoneyTransferRequested{} = event) do
    %MoneyTransferRequested{
      transfer_uuid: transfer_uuid,
      debit_account: debit_account,
      credit_account: credit_account,
      amount: amount
    } = event

    %TransferMoneyProcessManager{
      transfer
      | transfer_uuid: transfer_uuid,
        debit_account: debit_account,
        credit_account: credit_account,
        amount: amount,
        status: :withdraw_money_from_debit_account
    }
  end

  def apply(%TransferMoneyProcessManager{} = transfer, %MoneyWithdrawn{}) do
    %TransferMoneyProcessManager{transfer | status: :deposit_money_in_credit_account}
  end

  def apply(%TransferMoneyProcessManager{} = transfer, %MoneyDeposited{}) do
    %TransferMoneyProcessManager{transfer | status: :transfer_complete}
  end
end
