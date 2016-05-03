defmodule Commanded.ExampleDomain.OpenAccountHandler do
  alias Commanded.ExampleDomain.BankAccount
  alias Commanded.ExampleDomain.BankAccount.Commands.OpenAccount

  @behaviour Commanded.Commands.Handler

  def handle(state = %BankAccount{}, %OpenAccount{account_number: account_number, initial_balance: initial_balance}) do
    state
    |> BankAccount.open_account(account_number, initial_balance)
  end
end
