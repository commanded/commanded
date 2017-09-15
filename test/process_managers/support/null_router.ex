defmodule Commanded.ProcessManagers.NullRouter do
  @moduledoc false
  use Commanded.Commands.Router

  alias Commanded.ExampleDomain.BankAccount
  alias Commanded.ExampleDomain.BankAccount.Commands.WithdrawMoney
  alias Commanded.ProcessManagers.NullHandler

  dispatch WithdrawMoney, to: NullHandler, aggregate: BankAccount, identity: :account_number
end
