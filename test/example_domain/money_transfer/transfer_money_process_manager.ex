defmodule Commanded.ExampleDomain.TransferMoneyProcessManager do
  defstruct commands: [], transfer_uuid: nil, source_account: nil, target_account: nil, amount: nil, status: nil

  alias Commanded.ExampleDomain.TransferMoneyProcessManager
  alias Commanded.ExampleDomain.MoneyTransfer.Events.{MoneyTransferRequested,ReverseMoneyTransferRequested}
  alias Commanded.ExampleDomain.BankAccount.Events.{MoneyDeposited,MoneyWithdrawn}
  alias Commanded.ExampleDomain.BankAccount.Commands.{DepositMoney,WithdrawMoney}

  def interested?(%MoneyTransferRequested{transfer_uuid: transfer_uuid}), do: {:start, transfer_uuid}
  def interested?(%MoneyWithdrawn{transfer_uuid: transfer_uuid}), do: {:continue, transfer_uuid}
  def interested?(%MoneyDeposited{transfer_uuid: transfer_uuid}), do: {:continue, transfer_uuid}
  def interested?(%ReverseMoneyTransferRequested{transfer_uuid: transfer_uuid}), do: {:continue, transfer_uuid}
  def interested?(_event), do: false

  def new(process_uuid) do
    %TransferMoneyProcessManager{transfer_uuid: process_uuid}
  end

  def handle(%TransferMoneyProcessManager{transfer_uuid: transfer_uuid} = transfer, %MoneyTransferRequested{source_account: source_account, target_account: target_account, amount: amount}) do
    transfer =
      transfer
      |> dispatch(%WithdrawMoney{account_number: source_account, transfer_uuid: transfer_uuid, amount: amount})

    %TransferMoneyProcessManager{transfer |
      source_account: source_account,
      target_account: target_account,
      amount: amount,
      status: :withdraw_money_from_source_account
    }
  end

  def handle(%TransferMoneyProcessManager{transfer_uuid: transfer_uuid, status: :reverse_transfer} = transfer, %MoneyWithdrawn{} = _money_withdrawn) do
    transfer
    |> dispatch(%DepositMoney{account_number: transfer.source_account, transfer_uuid: transfer_uuid, amount: transfer.amount})
  end

  def handle(%TransferMoneyProcessManager{transfer_uuid: transfer_uuid} = transfer, %MoneyWithdrawn{} = _money_withdrawn) do
    transfer =
      transfer
      |> dispatch(%DepositMoney{account_number: transfer.target_account, transfer_uuid: transfer_uuid, amount: transfer.amount})

    %TransferMoneyProcessManager{transfer |
      status: :deposit_money_in_target_account
    }
  end

  def handle(%TransferMoneyProcessManager{} = transfer, %MoneyDeposited{} = _money_deposited) do
    %TransferMoneyProcessManager{transfer |
      status: :transfer_complete
    }
  end

  def handle(%TransferMoneyProcessManager{transfer_uuid: transfer_uuid, source_account: source_account, target_account: target_account, amount: amount} = transfer, %ReverseMoneyTransferRequested{}) do
    transfer =
      transfer
      |> dispatch(%WithdrawMoney{account_number: target_account, transfer_uuid: transfer_uuid, amount: amount})

    %TransferMoneyProcessManager{transfer |
      status: :reverse_transfer
    }
  end

  def handle(_transfer, _event) do
      # ignore any other events
  end

  defp dispatch(%TransferMoneyProcessManager{commands: commands} = transfer, command) do
    %TransferMoneyProcessManager{transfer |
      commands: [command | commands]
    }
  end
end
