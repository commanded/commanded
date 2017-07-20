defmodule Commanded.ExampleDomain.BankRouter do
  use Commanded.Commands.Router

  alias Commanded.ExampleDomain.{OpenAccountHandler,DepositMoneyHandler,TransferMoneyHandler,WithdrawMoneyHandler}
  alias Commanded.ExampleDomain.{BankAccount,MoneyTransfer}
  alias Commanded.ExampleDomain.BankAccount.Commands.{OpenAccount,DepositMoney,WithdrawMoney}
  alias Commanded.ExampleDomain.MoneyTransfer.Commands.{TransferMoney}

  dispatch OpenAccount, to: OpenAccountHandler, aggregate: BankAccount, identity: :account_number
  dispatch DepositMoney, to: DepositMoneyHandler, aggregate: BankAccount, identity: :account_number
  dispatch WithdrawMoney, to: WithdrawMoneyHandler, aggregate: BankAccount, identity: :account_number

  dispatch TransferMoney, to: TransferMoneyHandler, aggregate: MoneyTransfer, identity: :transfer_uuid
end
