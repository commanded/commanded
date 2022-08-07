defmodule Commanded.AggregateCaseTest do
  use Commanded.AggregateCase, aggregate: Commanded.Aggregate.Multi.BankAccount, async: true

  alias Commanded.Aggregate.Multi.BankAccount
  alias Commanded.Aggregate.Multi.BankAccount.Commands.DepositMoney
  alias Commanded.Aggregate.Multi.BankAccount.Commands.OpenAccount
  alias Commanded.Aggregate.Multi.BankAccount.Commands.WithdrawMoney
  alias Commanded.Aggregate.Multi.BankAccount.Events.BankAccountOpened
  alias Commanded.Aggregate.Multi.BankAccount.Events.MoneyDeposited
  alias Commanded.Aggregate.Multi.BankAccount.Events.MoneyWithdrawn
  alias Commanded.UUID

  describe "aggregate case" do
    test "`assert_events/2`" do
      assert_events(
        %OpenAccount{account_number: "acc123", initial_balance: 1_000},
        %BankAccountOpened{account_number: "acc123", balance: 1_000}
      )
    end

    test "`assert_events/3` with single historical event" do
      assert_events(
        %BankAccountOpened{account_number: "acc123", balance: 1_000},
        %DepositMoney{account_number: "acc123", amount: 500},
        %MoneyDeposited{account_number: "acc123", amount: 500, balance: 1_500}
      )
    end

    test "`assert_events/3` with list of historical events" do
      assert_events(
        [
          %BankAccountOpened{account_number: "acc123", balance: 1_000},
          %MoneyDeposited{account_number: "acc123", amount: 500, balance: 1_500}
        ],
        %DepositMoney{account_number: "acc123", amount: 500},
        %MoneyDeposited{account_number: "acc123", amount: 500, balance: 2_000}
      )
    end

    test "`assert_events/3` with `Commanded.Aggregate.Multi` command function" do
      transfer_uuid = UUID.uuid4()

      assert_events(
        [
          %BankAccountOpened{account_number: "acc123", balance: 1_000},
          %MoneyDeposited{account_number: "acc123", amount: 500, balance: 1_500}
        ],
        %WithdrawMoney{account_number: "acc123", transfer_uuid: transfer_uuid, amount: 200},
        %MoneyWithdrawn{
          account_number: "acc123",
          transfer_uuid: transfer_uuid,
          amount: 200,
          balance: 1_300
        }
      )
    end

    test "`assert_state/2`" do
      assert_state(
        %OpenAccount{account_number: "acc123", initial_balance: 1_000},
        %BankAccount{account_number: "acc123", balance: 1_000, status: :active}
      )
    end

    test "`assert_state/3`" do
      assert_state(
        %BankAccountOpened{account_number: "acc123", balance: 1_000},
        %DepositMoney{account_number: "acc123", amount: 500},
        %BankAccount{account_number: "acc123", balance: 1_500, status: :active}
      )
    end

    test "`assert_error/2`" do
      assert_error(
        %OpenAccount{account_number: "acc123", initial_balance: -100},
        {:error, :invalid_balance}
      )
    end

    test "`assert_error/3`" do
      assert_error(
        %BankAccountOpened{account_number: "acc123", balance: 1_000},
        %DepositMoney{account_number: "acc123", amount: -100},
        {:error, :invalid_amount}
      )
    end

    test "`assert_error/3` with `Commanded.Aggregate.Multi` command function" do
      transfer_uuid = UUID.uuid4()

      assert_error(
        [
          %BankAccountOpened{account_number: "acc123", balance: 1_000},
          %MoneyDeposited{account_number: "acc123", amount: 500, balance: 1_500}
        ],
        %WithdrawMoney{account_number: "acc123", transfer_uuid: transfer_uuid, amount: 2_000},
        {:error, :insufficient_funds_available}
      )
    end
  end
end
