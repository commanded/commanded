defmodule Commanded.ExampleDomain.TransferMoneyProcessManager do
  @moduledoc false
  use Commanded.ProcessManagers.ProcessManager,
    name: "transfer_money_process_manager",
    router: Commanded.ExampleDomain.BankRouter

  defstruct [
    transfer_uuid: nil,
    debit_account: nil,
    credit_account: nil,
    amount: nil,
    status: nil
  ]

  alias Commanded.ExampleDomain.TransferMoneyProcessManager
  alias Commanded.ExampleDomain.MoneyTransfer.Events.{MoneyTransferRequested}
  alias Commanded.ExampleDomain.BankAccount.Events.{MoneyDeposited,MoneyWithdrawn}
  alias Commanded.ExampleDomain.BankAccount.Commands.{DepositMoney,WithdrawMoney}

  def interested?(%MoneyTransferRequested{transfer_uuid: transfer_uuid}), do: {:start, transfer_uuid}
  def interested?(%MoneyWithdrawn{transfer_uuid: transfer_uuid}), do: {:continue, transfer_uuid}
  def interested?(%MoneyDeposited{transfer_uuid: transfer_uuid}), do: {:continue, transfer_uuid}
  def interested?(_event), do: false

  def handle(%TransferMoneyProcessManager{}, %MoneyTransferRequested{transfer_uuid: transfer_uuid, debit_account: debit_account, amount: amount}) do
    %WithdrawMoney{account_number: debit_account, transfer_uuid: transfer_uuid, amount: amount}
  end

  def handle(%TransferMoneyProcessManager{transfer_uuid: transfer_uuid, credit_account: credit_account, amount: amount}, %MoneyWithdrawn{}) do
    %DepositMoney{account_number: credit_account, transfer_uuid: transfer_uuid, amount: amount}
  end

  def handle(%TransferMoneyProcessManager{}, %MoneyDeposited{}), do: []

  ## state mutators

  def apply(%TransferMoneyProcessManager{} = transfer, %MoneyTransferRequested{transfer_uuid: transfer_uuid, debit_account: debit_account, credit_account: credit_account, amount: amount}) do
    %TransferMoneyProcessManager{transfer |
      transfer_uuid: transfer_uuid,
      debit_account: debit_account,
      credit_account: credit_account,
      amount: amount,
      status: :withdraw_money_from_debit_account
    }
  end

  def apply(%TransferMoneyProcessManager{} = transfer, %MoneyWithdrawn{}) do
    %TransferMoneyProcessManager{transfer |
      status: :deposit_money_in_credit_account
    }
  end

  def apply(%TransferMoneyProcessManager{} = transfer, %MoneyDeposited{}) do
    %TransferMoneyProcessManager{transfer |
      status: :transfer_complete
    }
  end
end
