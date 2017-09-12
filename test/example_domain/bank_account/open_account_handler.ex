defmodule Commanded.ExampleDomain.OpenAccountHandler do
  @moduledoc false
  alias Commanded.ExampleDomain.BankAccount
  alias Commanded.ExampleDomain.BankAccount.Commands.{OpenAccount,CloseAccount}

  @behaviour Commanded.Commands.Handler

  def handle(%BankAccount{} = aggregate, %OpenAccount{} = open_account) do
    aggregate
    |> BankAccount.open_account(open_account)
  end

  def handle(%BankAccount{} = aggregate, %CloseAccount{} = close_account) do
    aggregate
    |> BankAccount.close_account(close_account)
  end
end
