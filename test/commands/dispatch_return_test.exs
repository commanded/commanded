defmodule Commanded.Commands.DispatchReturnTest do
  use ExUnit.Case

  alias Commanded.Commands.ExecutionResult
  alias Commanded.ExampleDomain.BankApp
  alias Commanded.ExampleDomain.BankAccount
  alias Commanded.ExampleDomain.BankAccount.Commands.DepositMoney
  alias Commanded.ExampleDomain.BankAccount.Commands.OpenAccount
  alias Commanded.ExampleDomain.BankAccount.Events.BankAccountOpened
  alias Commanded.Helpers.CommandAuditMiddleware

  setup do
    start_supervised!(BankApp)
    start_supervised!(CommandAuditMiddleware)
    :ok
  end

  describe "dispatch return disabled" do
    test "should return `:ok`" do
      command = %OpenAccount{account_number: "ACC123", initial_balance: 1_000}

      assert :ok == BankApp.dispatch(command, returning: false)
    end

    test "should return an error on failure" do
      command = %OpenAccount{account_number: "ACC123", initial_balance: -1}

      assert {:error, :invalid_initial_balance} ==
               BankApp.dispatch(command, returning: false)
    end
  end

  describe "dispatch return aggregate state" do
    test "should return aggregate's updated state" do
      assert {:ok, %BankAccount{account_number: "ACC123", balance: 1_000, state: :active}} ==
               BankApp.dispatch(
                 %OpenAccount{account_number: "ACC123", initial_balance: 1_000},
                 returning: :aggregate_state
               )

      assert {:ok, %BankAccount{account_number: "ACC123", balance: 1_100, state: :active}} ==
               BankApp.dispatch(
                 %DepositMoney{account_number: "ACC123", amount: 100},
                 returning: :aggregate_state
               )
    end

    test "should return an error on failure" do
      command = %OpenAccount{account_number: "ACC123", initial_balance: -1}

      assert {:error, :invalid_initial_balance} ==
               BankApp.dispatch(command, returning: :aggregate_state)
    end
  end

  describe "dispatch return aggregate version" do
    test "should return aggregate's updated version" do
      assert {:ok, 1} ==
               BankApp.dispatch(
                 %OpenAccount{account_number: "ACC123", initial_balance: 1_000},
                 returning: :aggregate_version
               )

      assert {:ok, 2} ==
               BankApp.dispatch(
                 %DepositMoney{account_number: "ACC123", amount: 100},
                 returning: :aggregate_version
               )
    end

    test "should return an error on failure" do
      command = %OpenAccount{account_number: "ACC123", initial_balance: -1}

      assert {:error, :invalid_initial_balance} ==
               BankApp.dispatch(command, returning: :aggregate_version)
    end
  end

  describe "dispatch return execution result" do
    test "should return created events" do
      metadata = %{"ip_address" => "127.0.0.1"}
      command = %OpenAccount{account_number: "ACC123", initial_balance: 1_000}

      assert BankApp.dispatch(command, metadata: metadata, returning: :execution_result) ==
               {
                 :ok,
                 %ExecutionResult{
                   aggregate_uuid: "ACC123",
                   aggregate_state: %BankAccount{
                     account_number: "ACC123",
                     balance: 1_000,
                     state: :active
                   },
                   aggregate_version: 1,
                   events: [%BankAccountOpened{account_number: "ACC123", initial_balance: 1_000}],
                   metadata: metadata
                 }
               }
    end

    test "should return an error on failure" do
      command = %OpenAccount{account_number: "ACC123", initial_balance: -1}

      assert {:error, :invalid_initial_balance} ==
               BankApp.dispatch(command, returning: :execution_result)
    end
  end

  describe "dispatch include aggregate version" do
    test "should return aggregate's updated version" do
      assert {:ok, 1} ==
               BankApp.dispatch(
                 %OpenAccount{account_number: "ACC123", initial_balance: 1_000},
                 include_aggregate_version: true
               )

      assert {:ok, 2} ==
               BankApp.dispatch(
                 %DepositMoney{account_number: "ACC123", amount: 100},
                 include_aggregate_version: true
               )
    end
  end

  describe "dispatch include execution result" do
    test "should return created events" do
      metadata = %{"ip_address" => "127.0.0.1"}
      command = %OpenAccount{account_number: "ACC123", initial_balance: 1_000}

      assert BankApp.dispatch(command,
               metadata: metadata,
               include_execution_result: true
             ) ==
               {
                 :ok,
                 %ExecutionResult{
                   aggregate_uuid: "ACC123",
                   aggregate_state: %BankAccount{
                     account_number: "ACC123",
                     balance: 1_000,
                     state: :active
                   },
                   aggregate_version: 1,
                   events: [%BankAccountOpened{account_number: "ACC123", initial_balance: 1_000}],
                   metadata: metadata
                 }
               }
    end
  end

  describe "application dispatch return aggregate state" do
    alias Commanded.Commands.DefaultDispatchReturnApp

    setup do
      start_supervised!(DefaultDispatchReturnApp)
      :ok
    end

    test "should return aggregate's updated version" do
      assert {:ok, 1} ==
               DefaultDispatchReturnApp.dispatch(%OpenAccount{
                 account_number: "ACC123",
                 initial_balance: 1_000
               })

      assert {:ok, 2} ==
               DefaultDispatchReturnApp.dispatch(%DepositMoney{
                 account_number: "ACC123",
                 amount: 100
               })
    end

    test "should allow default to be overridden during dispatch" do
      assert {:ok, 1} ==
               DefaultDispatchReturnApp.dispatch(%OpenAccount{
                 account_number: "ACC123",
                 initial_balance: 1_000
               })

      assert {:ok, 2} ==
               DefaultDispatchReturnApp.dispatch(%DepositMoney{
                 account_number: "ACC123",
                 amount: 100
               })
    end
  end
end
