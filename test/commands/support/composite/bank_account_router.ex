defmodule Commanded.Commands.Composite.BankAccountRouter do
  @moduledoc false

  use Commanded.Commands.Router

  alias Commanded.ExampleDomain.{
    BankAccount,
    DepositMoneyHandler,
    OpenAccountHandler,
    WithdrawMoneyHandler
  }

  alias Commanded.ExampleDomain.BankAccount.Commands.{DepositMoney, OpenAccount, WithdrawMoney}

  identify BankAccount, by: :account_number

  dispatch OpenAccount, to: OpenAccountHandler, aggregate: BankAccount
  dispatch DepositMoney, to: DepositMoneyHandler, aggregate: BankAccount
  dispatch WithdrawMoney, to: WithdrawMoneyHandler, aggregate: BankAccount
end
