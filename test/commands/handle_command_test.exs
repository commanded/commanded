defmodule Commanded.Commands.HandleCommandTest do
  use ExUnit.Case
  doctest Commanded.CommandHandler

  alias Commanded.ExampleDomain.BankAccount
  alias Commanded.ExampleDomain.BankAccount.Commands.OpenAccount

  defmodule OpenAccountCommandHandler do
    @behaviour Commanded.CommandHandler

    def aggregate, do: BankAccount

    def handle(state = %BankAccount{}, %OpenAccount{account_number: account_number, initial_balance: initial_balance} = open_account) do
      state
      |> BankAccount.open_account(account_number, initial_balance)
    end
  end

  test "command handler implements behaviour" do
    bank_account =
      BankAccount.new("1")
      |> OpenAccountCommandHandler.handle(%OpenAccount{account_number: "ACC123", initial_balance: 1_000})

    assert bank_account.state.account_number == "ACC123"
    assert length(bank_account.events) == 1
    assert bank_account.version == 1
  end
end
