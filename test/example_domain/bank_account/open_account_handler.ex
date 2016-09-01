defmodule Commanded.ExampleDomain.OpenAccountHandler do
  alias Commanded.ExampleDomain.BankAccount
  alias Commanded.ExampleDomain.BankAccount.Commands.OpenAccount

  @behaviour Commanded.Commands.Handler

  def handle(%BankAccount{} = aggregate, %OpenAccount{} = open_account) do
    aggregate
    |> BankAccount.open_account(open_account)
  end
end
