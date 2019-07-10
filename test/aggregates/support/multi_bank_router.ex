defmodule Commanded.Aggregate.MultiBankRouter do
  use Commanded.Commands.Router

  alias Commanded.Aggregate.Multi.BankAccount
  alias Commanded.Aggregate.Multi.BankAccount.Commands.{OpenAccount, WithdrawMoney}

  dispatch [OpenAccount, WithdrawMoney], to: BankAccount, identity: :account_number
end
