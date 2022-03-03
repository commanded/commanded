defmodule Commanded.ExampleDomain.OpenAccountHandler do
  @moduledoc false

  @behaviour Commanded.Commands.Handler

  alias Commanded.ExampleDomain.BankAccount
  alias Commanded.ExampleDomain.BankAccount.Commands.{CloseAccount, OpenAccount}

  def handle(%BankAccount{} = aggregate, %OpenAccount{} = open_account) do
    BankAccount.open_account(aggregate, open_account)
  end

  def handle(%BankAccount{} = aggregate, %CloseAccount{} = close_account) do
    BankAccount.close_account(aggregate, close_account)
  end
end
