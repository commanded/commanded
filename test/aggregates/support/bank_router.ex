defmodule Commanded.Aggregates.BankRouter do
  @moduledoc false
  use Commanded.Commands.Router

  alias Commanded.ExampleDomain.{
    BankAccount,
    DepositMoneyHandler,
    OpenAccountHandler,
    WithdrawMoneyHandler
  }

  alias BankAccount.Commands.{CloseAccount, DepositMoney, OpenAccount, WithdrawMoney}

  identify BankAccount, by: :account_number

  dispatch OpenAccount, to: OpenAccountHandler, aggregate: BankAccount
  dispatch DepositMoney, to: DepositMoneyHandler, aggregate: BankAccount
  dispatch WithdrawMoney, to: WithdrawMoneyHandler, aggregate: BankAccount
  dispatch CloseAccount, to: OpenAccountHandler, aggregate: BankAccount
end
