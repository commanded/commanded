defmodule Commanded.ExampleDomain.BankRouter do
  @moduledoc false

  use Commanded.Commands.Router

  alias Commanded.ExampleDomain.BankAccount
  alias Commanded.ExampleDomain.BankAccount.Commands.CloseAccount
  alias Commanded.ExampleDomain.BankAccount.Commands.DepositMoney
  alias Commanded.ExampleDomain.BankAccount.Commands.OpenAccount
  alias Commanded.ExampleDomain.BankAccount.Commands.WithdrawMoney
  alias Commanded.ExampleDomain.DepositMoneyHandler
  alias Commanded.ExampleDomain.MoneyTransfer
  alias Commanded.ExampleDomain.MoneyTransfer.Commands.TransferMoney
  alias Commanded.ExampleDomain.OpenAccountHandler
  alias Commanded.ExampleDomain.TransferMoneyHandler
  alias Commanded.ExampleDomain.WithdrawMoneyHandler
  alias Commanded.Helpers.CommandAuditMiddleware

  middleware CommandAuditMiddleware

  # Bank account
  identify BankAccount, by: :account_number
  dispatch OpenAccount, to: OpenAccountHandler, aggregate: BankAccount
  dispatch DepositMoney, to: DepositMoneyHandler, aggregate: BankAccount
  dispatch WithdrawMoney, to: WithdrawMoneyHandler, aggregate: BankAccount
  dispatch CloseAccount, to: OpenAccountHandler, aggregate: BankAccount

  # Money transfer
  identify MoneyTransfer, by: :transfer_uuid
  dispatch TransferMoney, to: TransferMoneyHandler, aggregate: MoneyTransfer
end
