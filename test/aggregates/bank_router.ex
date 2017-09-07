defmodule Commanded.Aggregates.BankRouter do
  use Commanded.Commands.Router

  alias Commanded.Aggregates.BankAccountLifespan
  alias Commanded.ExampleDomain.BankAccount.Commands.{
    OpenAccount,
    DepositMoney,
    WithdrawMoney,
  }
  alias Commanded.ExampleDomain.{
    OpenAccountHandler,
    DepositMoneyHandler,
    WithdrawMoneyHandler,
  }

  dispatch OpenAccount, to: OpenAccountHandler, aggregate: BankAccount, lifespan: BankAccountLifespan, identity: :account_number
  dispatch DepositMoney, to: DepositMoneyHandler, aggregate: BankAccount, lifespan: BankAccountLifespan, identity: :account_number
  dispatch WithdrawMoney, to: WithdrawMoneyHandler, aggregate: BankAccount, identity: :account_number
end
