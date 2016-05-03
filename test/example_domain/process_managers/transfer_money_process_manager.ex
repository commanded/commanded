defmodule Commanded.ExampleDomain.TransferMoneyProcessManager do
  alias Commanded.ExampleDomain.MoneyTransfer.Events.MoneyTransferRequested

  defstruct state: nil, commands: []

  defmodule State do
    defstruct source_account: nil, target_account: nil, amount: nil, status: nil
  end

  alias Commanded.ExampleDomain.TransferMoneyProcessManager.State
  alias Commanded.ExampleDomain.BankAccount.Commands.{DepositMoney,WithdrawMoney}

  def handle(%State{} = transfer, %MoneyTransferRequested{source_account: source_account, target_account: target_account, amount: amount}) do
    transfer
    |> dispatch_command(%WithdrawMoney{aggregate_uuid: source_account, amount: amount})
    |> update(fn state -> %{state |
      source_account: source_account,
      target_account: target_account,
      amount: target_account,
      status: :withdraw_money_from_source_account
    } end)
  end

  def handle(%State{} = state, %MoneyWithdrawn{} = transfer_requested) do
    transfer
    |> dispatch_command(%DepositMoney{})
    |> update(fn state -> %{state |
      status: :deposit_money_in_target_account
    } end)
  end

  defp dispatch_command(state, command) do
    %{state | commands: [command|commands]}
  end
end
