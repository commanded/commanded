defmodule Commanded.Commands.RegisterCommandHandlerTest do
  use ExUnit.Case
  doctest Commanded.CommandRegistry

  alias Commanded.CommandRegistry
  alias Commanded.ExampleDomain.{BankAccount,OpenAccountHandler}
  alias Commanded.ExampleDomain.BankAccount.Commands.OpenAccount

  setup do
    {:ok, command_registry} = CommandRegistry.start_link
    :ok
  end

  test "register command handler" do
    :ok = CommandRegistry.register(OpenAccount, OpenAccountHandler)

    {:ok, handler} = CommandRegistry.handler(OpenAccount)
    assert handler == OpenAccountHandler
  end

  test "don't allow duplicate registrations for a command" do
    :ok = CommandRegistry.register(OpenAccount, OpenAccountHandler)
    {:error, :already_registered} = CommandRegistry.register(OpenAccount, OpenAccountHandler)
  end
end
