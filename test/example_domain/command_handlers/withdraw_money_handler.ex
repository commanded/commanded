defmodule Commanded.ExampleDomain.WithdrawMoneyHandler do
  alias Commanded.ExampleDomain.BankAccount
  alias Commanded.ExampleDomain.BankAccount.Commands.WithdrawMoney

  @behaviour Commanded.Commands.Handler

  def handle(%BankAccount{} = state, %WithdrawMoney{amount: amount}) do
    state
    |> BankAccount.withdraw(amount)
  end
end
