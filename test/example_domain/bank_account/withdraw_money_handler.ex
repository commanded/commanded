defmodule Commanded.ExampleDomain.WithdrawMoneyHandler do
  @moduledoc false
  alias Commanded.ExampleDomain.BankAccount
  alias Commanded.ExampleDomain.BankAccount.Commands.WithdrawMoney

  @behaviour Commanded.Commands.Handler

  def handle(%BankAccount{} = aggregate, %WithdrawMoney{} = withdraw_money) do
    aggregate
    |> BankAccount.withdraw(withdraw_money)
  end
end
