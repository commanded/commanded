defmodule Commanded.ExampleDomain.TransferMoneyHandler do
  alias Commanded.ExampleDomain.MoneyTransfer
  alias Commanded.ExampleDomain.MoneyTransfer.Commands.TransferMoney

  @behaviour Commanded.Commands.Handler

  def handle(%MoneyTransfer{} = state, %TransferMoney{source_account: source_account, target_account: target_account, amount: amount}) do
    state
    |> MoneyTransfer.transfer_money(source_account, target_account, amount)
  end
end
