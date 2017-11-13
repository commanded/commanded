defmodule Commanded.Commands.CompositeRouterTest do
  use Commanded.StorageCase

  alias Commanded.ExampleDomain.{BankAccount,MoneyTransfer}
  alias Commanded.ExampleDomain.{OpenAccountHandler,DepositMoneyHandler,TransferMoneyHandler,WithdrawMoneyHandler}
  alias Commanded.ExampleDomain.BankAccount.Commands.{OpenAccount,DepositMoney,WithdrawMoney}
  alias Commanded.ExampleDomain.MoneyTransfer.Commands.TransferMoney
  alias Commanded.Commands.ExecutionResult

  defmodule UnregisteredCommand do
    @moduledoc false
    defstruct [:uuid]
  end

  defmodule BankAccountRouter do
    @moduledoc false
    use Commanded.Commands.Router

    identify BankAccount, by: :account_number

    dispatch OpenAccount, to: OpenAccountHandler, aggregate: BankAccount
    dispatch DepositMoney, to: DepositMoneyHandler, aggregate: BankAccount
    dispatch WithdrawMoney, to: WithdrawMoneyHandler, aggregate: BankAccount
  end

  defmodule MoneyTransferRouter do
    @moduledoc false
    use Commanded.Commands.Router

    identify MoneyTransfer, by: :transfer_uuid
    dispatch TransferMoney, to: TransferMoneyHandler, aggregate: MoneyTransfer
  end

  defmodule ExampleCompositeRouter do
    @moduledoc false
    use Commanded.Commands.CompositeRouter

    router BankAccountRouter
    router MoneyTransferRouter
  end

  describe "composite router" do
    test "should dispatch command to registered handler" do
      assert :ok = ExampleCompositeRouter.dispatch(%OpenAccount{account_number: "ACC123", initial_balance: 1_000})
      assert :ok = ExampleCompositeRouter.dispatch(%TransferMoney{transfer_uuid: UUID.uuid4(), debit_account: "ACC123", credit_account: "ACC456", amount: 500})
    end

    test "should dispatch command to registered handler with options" do
      command = %OpenAccount{account_number: "ACC123", initial_balance: 1_000}
      assert {:ok, %ExecutionResult{}} = ExampleCompositeRouter.dispatch(command, include_execution_result: true)
    end

    test "should fail to dispatch unregistered command" do
      assert {:error, :unregistered_command} = ExampleCompositeRouter.dispatch(%UnregisteredCommand{})
    end

    test "should fail to compile when duplicate commands registered" do
      assert_raise RuntimeError, "duplicate registration for Commanded.ExampleDomain.MoneyTransfer.Commands.TransferMoney command, registered in both Commanded.Commands.CompositeRouterTest.MoneyTransferRouter and DuplicateMoneyTransferRouter", fn ->
        Code.eval_string """
          alias Commanded.ExampleDomain.{MoneyTransfer,TransferMoneyHandler}
          alias Commanded.ExampleDomain.MoneyTransfer.Commands.TransferMoney
          alias Commanded.Commands.CompositeRouterTest.MoneyTransferRouter

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
        """
      end
    end
  end
end
