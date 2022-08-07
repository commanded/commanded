defmodule Commanded.Commands.CommandIdentityTest do
  use ExUnit.Case

  alias Commanded.ExampleDomain.BankAccount.Commands.OpenAccount
  alias Commanded.ExampleDomain.BankApp
  alias Commanded.Helpers.CommandAuditMiddleware
  alias Commanded.UUID

  setup do
    start_supervised!(CommandAuditMiddleware)
    start_supervised!(BankApp)

    :ok
  end

  describe "provide command identity" do
    test "should generate a command_uuid if none is provided" do
      command = %OpenAccount{account_number: "ACC123", initial_balance: 1_000}
      :ok = BankApp.dispatch(command)
      [command_uuid] = CommandAuditMiddleware.dispatched_commands(& &1.command_uuid)
      assert is_binary(UUID.string_to_binary!(command_uuid))
    end

    test "should accept provided command_uuid" do
      command = %OpenAccount{account_number: "ACC123", initial_balance: 1_000}
      command_uuid = UUID.uuid4()
      :ok = BankApp.dispatch(command, command_uuid: command_uuid)
      assert [^command_uuid] = CommandAuditMiddleware.dispatched_commands(& &1.command_uuid)
    end
  end
end
