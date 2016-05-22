defmodule Commanded.ExampleDomain.TransferMoneyProcessManager do
  defstruct commands: [], transfer_uuid: nil, source_account: nil, target_account: nil, amount: nil, status: nil

  alias Commanded.ExampleDomain.TransferMoneyProcessManager
  alias Commanded.ExampleDomain.MoneyTransfer.Events.{MoneyTransferRequested}
  alias Commanded.ExampleDomain.BankAccount.Events.{MoneyDeposited,MoneyWithdrawn}
  alias Commanded.ExampleDomain.BankAccount.Commands.{DepositMoney,WithdrawMoney}

  def interested?(%MoneyDeposited{transfer_uuid: transfer_uuid}), do: {:start, transfer_uuid}
  def interested?(%MoneyWithdrawn{transfer_uuid: transfer_uuid}), do: {:continue, transfer_uuid}
  def interested?(%MoneyDeposited{transfer_uuid: transfer_uuid}), do: {:continue, transfer_uuid}
  def interested?(_event), do: false

  def new(process_uuid) do
    %TransferMoneyProcessManager{transfer_uuid: process_uuid}
  end

  def handle(%TransferMoneyProcessManager{} = transfer, %MoneyTransferRequested{source_account: source_account, target_account: target_account, amount: amount}) do
    transfer =
      transfer
      |> dispatch(%WithdrawMoney{aggregate_uuid: source_account, amount: amount})

    %TransferMoneyProcessManager{transfer |
      source_account: source_account,
      target_account: target_account,
      amount: target_account,
      status: :withdraw_money_from_source_account
    }
  end

  def handle(%TransferMoneyProcessManager{} = transfer, %MoneyWithdrawn{} = money_withdrawn) do
    transfer =
      transfer
      |> dispatch(%DepositMoney{aggregate_uuid: transfer.state.target_account, amount: transfer.state.amount})

    %TransferMoneyProcessManager{transfer |
      status: :deposit_money_in_target_account
    }
  end

  def handle(%TransferMoneyProcessManager{} = transfer, %MoneyDeposited{} = money_deposited) do
    %TransferMoneyProcessManager{transfer |
      status: :transfer_complete
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
