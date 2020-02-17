defmodule Commanded.Commands.CompositeRouterTest do
  use ExUnit.Case

  alias Commanded.Commands.Composite.CompositeCompositeRouter
  alias Commanded.Commands.Composite.ExampleCompositeRouter
  alias Commanded.Commands.Composite.UnregisteredCommand
  alias Commanded.Commands.ExecutionResult
  alias Commanded.DefaultApp
  alias Commanded.ExampleDomain.BankAccount.Commands.{OpenAccount, DepositMoney, WithdrawMoney}
  alias Commanded.ExampleDomain.MoneyTransfer.Commands.TransferMoney

  describe "composite router" do
    setup do
      start_supervised!(DefaultApp)

      :ok
    end

    test "should register all commands" do
      assert ExampleCompositeRouter.__registered_commands__() |> Enum.sort() == [
               DepositMoney,
               OpenAccount,
               WithdrawMoney,
               TransferMoney
             ]
    end

    test "should dispatch command to registered handler" do
      assert :ok =
               ExampleCompositeRouter.dispatch(
                 %OpenAccount{
                   account_number: "ACC123",
                   initial_balance: 1_000
                 },
                 application: DefaultApp
               )

      assert :ok =
               ExampleCompositeRouter.dispatch(
                 %TransferMoney{
                   transfer_uuid: UUID.uuid4(),
                   debit_account: "ACC123",
                   credit_account: "ACC456",
                   amount: 500
                 },
                 application: DefaultApp
               )
    end

    test "should dispatch command to registered handler with options" do
      command = %OpenAccount{account_number: "ACC123", initial_balance: 1_000}

      assert {:ok, %ExecutionResult{}} =
               ExampleCompositeRouter.dispatch(command,
                 application: DefaultApp,
                 include_execution_result: true
               )
    end

    test "should fail to dispatch unregistered command" do
      assert {:error, :unregistered_command} =
               ExampleCompositeRouter.dispatch(%UnregisteredCommand{}, application: DefaultApp)
    end

    test "should fail to compile when duplicate commands registered" do
      assert_raise RuntimeError,
                   "duplicate registration for Commanded.ExampleDomain.MoneyTransfer.Commands.TransferMoney command, registered in both Commanded.Commands.Composite.MoneyTransferRouter and DuplicateMoneyTransferRouter",
                   fn ->
                     Code.eval_string("""
                       alias Commanded.ExampleDomain.{MoneyTransfer,TransferMoneyHandler}
                       alias Commanded.ExampleDomain.MoneyTransfer.Commands.TransferMoney
                       alias Commanded.Commands.Composite.MoneyTransferRouter

                       defmodule DuplicateMoneyTransferRouter do
                         use Commanded.Commands.Router

                         identify MoneyTransfer, by: :transfer_uuid
                         dispatch TransferMoney, to: TransferMoneyHandler, aggregate: MoneyTransfer
                       end

                       defmodule ExampleCompositeRouter do
                         use Commanded.Commands.CompositeRouter

                         router MoneyTransferRouter
                         router DuplicateMoneyTransferRouter
                       end
                     """)
                   end
    end
  end

  describe "composite router composed of composite router" do
    setup do
      start_supervised!(DefaultApp)

      :ok
    end

    test "should register all commands" do
      assert CompositeCompositeRouter.__registered_commands__() |> Enum.sort() == [
               DepositMoney,
               OpenAccount,
               WithdrawMoney,
               TransferMoney
             ]
    end

    test "should dispatch command to registered handler" do
      assert :ok =
               CompositeCompositeRouter.dispatch(
                 %OpenAccount{
                   account_number: "ACC123",
                   initial_balance: 1_000
                 },
                 application: DefaultApp
               )

      assert :ok =
               CompositeCompositeRouter.dispatch(
                 %TransferMoney{
                   transfer_uuid: UUID.uuid4(),
                   debit_account: "ACC123",
                   credit_account: "ACC456",
                   amount: 500
                 },
                 application: DefaultApp
               )
    end
  end
end
