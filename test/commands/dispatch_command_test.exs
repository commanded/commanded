defmodule Commanded.Commands.DispatchCommandTest do
  use ExUnit.Case
  doctest Commanded.Commands.Dispatcher

  alias Commanded.{Commands,Entities}
  alias Commanded.Commands.Dispatcher
  alias Commanded.ExampleDomain.OpenAccountHandler
  alias Commanded.ExampleDomain.BankAccount.Commands.OpenAccount

  setup do
    EventStore.Storage.reset!

    {:ok, _} = Commands.Registry.start_link
    {:ok, _} = Entities.Registry.start_link

    :ok
  end

  test "dispatch command to registered handler" do
    :ok = Commands.Registry.register(OpenAccount, OpenAccountHandler)
    :ok = Dispatcher.dispatch(%OpenAccount{account_number: "ACC123", initial_balance: 1_000})
  end
end
