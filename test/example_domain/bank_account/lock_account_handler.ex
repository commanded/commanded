defmodule Commanded.ExampleDomain.LockAccountHandler do
  @moduledoc false

  @behaviour Commanded.Commands.Handler

  alias Commanded.ExampleDomain.BankAccount
  alias Commanded.ExampleDomain.BankAccount.Commands.LockAccount

  def handle(%BankAccount{} = aggregate, %LockAccount{} = lock_account) do
    BankAccount.lock_account(aggregate, lock_account)
  end
end
