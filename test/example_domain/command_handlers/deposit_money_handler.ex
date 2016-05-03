defmodule Commanded.ExampleDomain.DepositMoneyHandler do
  alias Commanded.ExampleDomain.BankAccount
  alias Commanded.ExampleDomain.BankAccount.Commands.DepositMoney

  @behaviour Commanded.Commands.Handler

  def handle(%BankAccount{} = state, %DepositMoney{amount: amount}) do
    state
    |> BankAccount.deposit(amount)
  end
end
