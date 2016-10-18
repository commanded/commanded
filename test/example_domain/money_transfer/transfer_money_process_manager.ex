defmodule Commanded.ExampleDomain.TransferMoneyProcessManager do
  use Commanded.ProcessManagers.ProcessManager, fields: [
    source_account: nil,
    target_account: nil,
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

  def handle(%TransferMoneyProcessManager{process_uuid: transfer_uuid} = transfer, %MoneyTransferRequested{source_account: source_account, amount: amount} = money_transfer_requested) do
    transfer =
      transfer
      |> dispatch(%WithdrawMoney{account_number: source_account, transfer_uuid: transfer_uuid, amount: amount})
      |> update(money_transfer_requested)

    {:ok, transfer}
  end

  def handle(%TransferMoneyProcessManager{process_uuid: transfer_uuid, state: state} = transfer, %MoneyWithdrawn{} = money_withdrawn) do
    transfer =
      transfer
      |> dispatch(%DepositMoney{account_number: state.target_account, transfer_uuid: transfer_uuid, amount: state.amount})
      |> update(money_withdrawn)

    {:ok, transfer}
  end

  def handle(%TransferMoneyProcessManager{} = transfer, %MoneyDeposited{} = money_deposited) do
    transfer = update(transfer, money_deposited)

    {:ok, transfer}
  end

  def handle(transfer, _event) do
    # ignore any other events
    {:ok, transfer}
  end

  ## state mutators

  def apply(%TransferMoneyProcessManager.State{} = transfer, %MoneyTransferRequested{source_account: source_account, target_account: target_account, amount: amount}) do
    %TransferMoneyProcessManager.State{transfer |
      source_account: source_account,
      target_account: target_account,
      amount: amount,
      status: :withdraw_money_from_source_account
    }
  end

  def apply(%TransferMoneyProcessManager.State{} = transfer, %MoneyWithdrawn{}) do
    %TransferMoneyProcessManager.State{transfer |
      status: :deposit_money_in_target_account
    }
  end

  def apply(%TransferMoneyProcessManager.State{} = transfer, %MoneyDeposited{}) do
    %TransferMoneyProcessManager.State{transfer |
      status: :transfer_complete
    }
  end
end
