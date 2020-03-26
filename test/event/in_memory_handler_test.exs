defmodule Commanded.Event.InMemoryHandlerTest do
  use Commanded.StorageCase

  alias Commanded.Helpers.Wait
  alias Commanded.ExampleDomain.BankApp
  alias Commanded.ExampleDomain.BankAccount.Events.BankAccountOpened
  alias Commanded.ExampleDomain.BankAccount.Commands.OpenAccount
  alias Commanded.Helpers.CommandAuditMiddleware

  defmodule InMemoryHandler do
    @moduledoc false

    use Commanded.Event.Handler,
      application: Commanded.ExampleDomain.BankApp,
      name: __MODULE__,
      projection: :in_memory

    def init do
      Agent.start_link(fn -> 0 end, name: __MODULE__)
      :ok
    end

    def handle(%BankAccountOpened{}, _metadata) do
      Agent.update(__MODULE__, fn opened_count -> opened_count + 1 end)
      :ok
    end

    def event_count() do
      try do
        Agent.get(__MODULE__, fn opened_count -> opened_count end)
      catch
        :exit, _reason -> false
      end
    end
  end

  describe "in memory handler" do
    setup do
      start_supervised!(CommandAuditMiddleware)
      start_supervised!(BankApp)

      :ok = BankApp.dispatch(%OpenAccount{account_number: "ACC123", initial_balance: 1_000})
      :ok = BankApp.dispatch(%OpenAccount{account_number: "ACC456", initial_balance: 2_000})

      handler = start_supervised!(InMemoryHandler)

      [handler: handler]
    end

    test "recieves previous events" do
      Wait.until(fn ->
        assert InMemoryHandler.event_count() == 2
      end)
    end

    test "recieves new events" do
      :ok = BankApp.dispatch(%OpenAccount{account_number: "ACC789", initial_balance: 3_000})

      Wait.until(fn ->
        assert InMemoryHandler.event_count() == 3
      end)
    end
  end
end
