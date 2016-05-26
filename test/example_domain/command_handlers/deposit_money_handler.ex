defmodule Commanded.ExampleDomain.DepositMoneyHandler do
  alias Commanded.ExampleDomain.BankAccount
  alias Commanded.ExampleDomain.BankAccount.Commands.DepositMoney

  @behaviour Commanded.Commands.Handler

  def handle(%BankAccount{} = state, %DepositMoney{transfer_uuid: transfer_uuid, amount: amount}) do
    state
    |> BankAccount.deposit(transfer_uuid, amount)
  end
end
