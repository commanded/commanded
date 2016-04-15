defmodule Commanded.Commands.DispatchCommandTest do
  use ExUnit.Case
  doctest Commanded.Commands.Dispatcher

  alias Commanded.Commands
  alias Commanded.Commands.Dispatcher
  alias Commanded.ExampleDomain.OpenAccountHandler
  alias Commanded.ExampleDomain.BankAccount.Commands.OpenAccount

  defmodule UnregisteredCommand do
    defstruct entity_id: UUID.uuid4
  end

  setup do
    EventStore.Storage.reset!
    Commanded.Supervisor.start_link
    :ok
  end

  test "dispatch command to registered handler" do
    :ok = Commands.Registry.register(OpenAccount, OpenAccountHandler)
    :ok = Dispatcher.dispatch(%OpenAccount{account_number: "ACC123", initial_balance: 1_000})
  end

  test "should fail to dispatch unregistered command" do
    {:error, :unregistered_command} = Dispatcher.dispatch(%UnregisteredCommand{})
  end
end
