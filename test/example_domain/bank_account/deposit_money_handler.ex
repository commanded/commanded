defmodule Commanded.ExampleDomain.DepositMoneyHandler do
  @moduledoc false

  @behaviour Commanded.Commands.Handler

  alias Commanded.ExampleDomain.BankAccount
  alias Commanded.ExampleDomain.BankAccount.Commands.DepositMoney

  def handle(%BankAccount{} = aggregate, %DepositMoney{} = deposit_money) do
    aggregate
    |> BankAccount.deposit(deposit_money)
  end
end
