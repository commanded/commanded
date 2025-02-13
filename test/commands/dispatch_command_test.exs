defmodule Commanded.Commands.DispatchCommandTest do
  use ExUnit.Case

  alias Commanded.EventStore
  alias Commanded.ExampleDomain.BankAccount
  alias Commanded.ExampleDomain.BankAccount.Commands.{DepositMoney, OpenAccount}
  alias Commanded.ExampleDomain.{BankApp, BankRouter}
  alias Commanded.Helpers.CommandAuditMiddleware
  alias Commanded.UUID

  setup do
    start_supervised!(CommandAuditMiddleware)
    start_supervised!(BankApp)

    :ok
  end

  describe "dispatch command" do
    test "should be dispatched via an application" do
      command = %OpenAccount{account_number: "ACC123", initial_balance: 1_000}

      assert :ok = BankApp.dispatch(command)
    end

    test "should be dispatched via a router" do
      command = %OpenAccount{account_number: "ACC123", initial_balance: 1_000}

      assert :ok = BankRouter.dispatch(command, application: BankApp)
    end
  end

  describe "with event id from domain event" do
    test "should be used as causation id" do
      uuid = UUID.uuid4()

      assert {:ok, %BankAccount{account_number: "ACC123", balance: 1_000, state: :active}} ==
               BankApp.dispatch(
                 %OpenAccount{account_number: "ACC123", initial_balance: 1_000},
                 returning: :aggregate_state
               )

      BankApp.dispatch(
        %DepositMoney{
          account_number: "ACC123",
          amount: 100,
          transfer_uuid: uuid
        },
        returning: :aggregate_state
      )

      assert {:error, :duplicate_event} =
               BankApp.dispatch(
                 %DepositMoney{
                   account_number: "ACC123",
                   amount: 100,
                   transfer_uuid: uuid
                 },
                 returning: :aggregate_state
               )

      events = EventStore.stream_forward(BankApp, "ACC123")
      assert length(events) == 2
    end
  end
end
