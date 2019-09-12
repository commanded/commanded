defmodule Commanded.Commands.Composite.BankAccountRouter do
  @moduledoc false

  use Commanded.Commands.Router

  alias Commanded.ExampleDomain.BankAccount
  alias Commanded.ExampleDomain.BankAccount.Commands.{OpenAccount, DepositMoney, WithdrawMoney}
  alias Commanded.ExampleDomain.DepositMoneyHandler
  alias Commanded.ExampleDomain.OpenAccountHandler
  alias Commanded.ExampleDomain.WithdrawMoneyHandler

  identify BankAccount, by: :account_number

  dispatch OpenAccount, to: OpenAccountHandler, aggregate: BankAccount
  dispatch DepositMoney, to: DepositMoneyHandler, aggregate: BankAccount
  dispatch WithdrawMoney, to: WithdrawMoneyHandler, aggregate: BankAccount
end
