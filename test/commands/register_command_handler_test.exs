defmodule Commanded.Commands.RegisterCommandHandlerTest do
  use ExUnit.Case
  doctest Commanded.Commands.Registry

  alias Commanded.Commands.Registry
  alias Commanded.ExampleDomain.{BankAccount,OpenAccountHandler}
  alias Commanded.ExampleDomain.BankAccount.Commands.OpenAccount

  setup do
    {:ok, command_registry} = Registry.start_link
    :ok
  end

  test "register command handler" do
    :ok = Registry.register(OpenAccount, OpenAccountHandler)

    {:ok, handler} = Registry.handler(OpenAccount)
    assert handler == OpenAccountHandler
  end

  test "don't allow duplicate registrations for a command" do
    :ok = Registry.register(OpenAccount, OpenAccountHandler)
    {:error, :already_registered} = Registry.register(OpenAccount, OpenAccountHandler)
  end
end
