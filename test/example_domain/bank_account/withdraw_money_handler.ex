defmodule Commanded.ExampleDomain.WithdrawMoneyHandler do
  @moduledoc false

  @behaviour Commanded.Commands.Handler

  alias Commanded.ExampleDomain.BankAccount
  alias Commanded.ExampleDomain.BankAccount.Commands.WithdrawMoney

  def handle(%BankAccount{} = aggregate, %WithdrawMoney{} = withdraw_money) do
    BankAccount.withdraw(aggregate, withdraw_money)
  end
end
