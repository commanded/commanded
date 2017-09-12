defmodule Commanded.ExampleDomain.DepositMoneyHandler do
  @moduledoc false
  alias Commanded.ExampleDomain.BankAccount
  alias Commanded.ExampleDomain.BankAccount.Commands.DepositMoney

  @behaviour Commanded.Commands.Handler

  def handle(%BankAccount{} = aggregate, %DepositMoney{} = deposit_money) do
    aggregate
    |> BankAccount.deposit(deposit_money)
  end
end
