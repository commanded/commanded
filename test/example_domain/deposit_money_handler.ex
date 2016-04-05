defmodule Commanded.ExampleDomain.DepositMoneyHandler do
  alias Commanded.ExampleDomain.BankAccount
  alias Commanded.ExampleDomain.BankAccount.Commands.DepositMoney

  @behaviour Commanded.Commands.Handler

  def entity, do: BankAccount

  def handle(state = %BankAccount{}, %DepositMoney{amount: amount}) do
    state
    |> BankAccount.deposit(amount)
  end
end
