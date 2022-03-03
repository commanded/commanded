defmodule Commanded.Serialization.ModuleNameTypeProviderTest do
  use ExUnit.Case

  alias Commanded.ExampleDomain.BankAccount.Events.BankAccountOpened
  alias Commanded.Serialization.ModuleNameTypeProvider

  @account_opened_type "Elixir.Commanded.ExampleDomain.BankAccount.Events.BankAccountOpened"

  test "should convert an event to its type" do
    account_opened = %BankAccountOpened{account_number: "ACC123", initial_balance: 1_000}

    assert ModuleNameTypeProvider.to_string(account_opened) == @account_opened_type
  end

  test "should convert a type to its struct" do
    assert ModuleNameTypeProvider.to_struct(@account_opened_type) == %BankAccountOpened{}
  end

  defmodule NamedEvent do
    defstruct [:data]
  end

  defmodule AnotherNamedEvent do
    defstruct [:data]
  end

  test "should convert module struct to type" do
    assert "Elixir.Commanded.Serialization.ModuleNameTypeProviderTest.NamedEvent" ==
             ModuleNameTypeProvider.to_string(%NamedEvent{})

    assert "Elixir.Commanded.Serialization.ModuleNameTypeProviderTest.AnotherNamedEvent" ==
             ModuleNameTypeProvider.to_string(%AnotherNamedEvent{})
  end
end
