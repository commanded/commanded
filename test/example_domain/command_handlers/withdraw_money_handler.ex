defmodule Commanded.ExampleDomain.WithdrawMoneyHandler do
  alias Commanded.ExampleDomain.BankAccount
  alias Commanded.ExampleDomain.BankAccount.Commands.WithdrawMoney

  @behaviour Commanded.Commands.Handler

  def handle(%BankAccount{} = state, %WithdrawMoney{transfer_uuid: transfer_uuid, amount: amount}) do
    state
    |> BankAccount.withdraw(transfer_uuid, amount)
  end
end
