defmodule Commanded.Aggregate.Multi.BankAccount do
  defstruct [:account_number, :status, balance: 0]

  alias Commanded.Aggregate.Multi
  alias Commanded.Aggregate.Multi.BankAccount

  defmodule Commands do
    defmodule OpenAccount do
      defstruct [:account_number, :initial_balance]
    end

    defmodule DepositMoney do
      defstruct [:account_number, :amount]
    end

    defmodule WithdrawMoney do
      defstruct [:account_number, :transfer_uuid, :amount]
    end
  end

  defmodule Events do
    defmodule BankAccountOpened do
      @derive Jason.Encoder
      defstruct [:account_number, :balance]
    end

    defmodule MoneyDeposited do
      @derive Jason.Encoder
      defstruct [:account_number, :amount, :balance]
    end

    defmodule MoneyWithdrawn do
      @derive Jason.Encoder
      defstruct [:account_number, :transfer_uuid, :amount, :balance]
    end
  end

  alias Commands.{DepositMoney, OpenAccount, WithdrawMoney}
  alias Events.{BankAccountOpened, MoneyDeposited, MoneyWithdrawn}

  # Public command functions

  def execute(%BankAccount{status: nil}, %OpenAccount{} = command) do
    %OpenAccount{account_number: account_number, initial_balance: initial_balance} = command

    if is_number(initial_balance) and initial_balance > 0 do
      event = %BankAccountOpened{account_number: account_number, balance: initial_balance}

      {:ok, event}
    else
      {:error, :invalid_balance}
    end
  end

  def execute(%BankAccount{}, %OpenAccount{}), do: {:error, :account_exists}

  # Ignore any other commands for unopened accounts.
  def execute(%BankAccount{status: nil}, _command), do: {:error, :invalid_account}

  def execute(%BankAccount{status: :active} = account, %DepositMoney{} = command) do
    %BankAccount{account_number: account_number, balance: balance} = account
    %DepositMoney{amount: amount} = command

    if is_number(amount) and amount > 0 do
      event = %MoneyDeposited{
        account_number: account_number,
        amount: amount,
        balance: balance + amount
      }

      {:ok, event}
    else
      {:error, :invalid_amount}
    end
  end

  def execute(%BankAccount{status: :active} = account, %WithdrawMoney{} = command) do
    account
    |> Multi.new()
    |> Multi.execute(&withdraw_money(&1, command))
    |> Multi.execute(&check_balance/1)
  end

  # State mutators

  def apply(%BankAccount{} = state, %BankAccountOpened{} = event) do
    %BankAccountOpened{account_number: account_number, balance: balance} = event

    %BankAccount{state | account_number: account_number, balance: balance, status: :active}
  end

  def apply(%BankAccount{} = state, %MoneyDeposited{} = event) do
    %MoneyDeposited{balance: balance} = event

    %BankAccount{state | balance: balance}
  end

  def apply(%BankAccount{} = state, %MoneyWithdrawn{} = event) do
    %MoneyWithdrawn{balance: balance} = event

    %BankAccount{state | balance: balance}
  end

  # Private helpers

  defp withdraw_money(%BankAccount{} = state, %WithdrawMoney{} = command) do
    %BankAccount{account_number: account_number, balance: balance} = state
    %WithdrawMoney{transfer_uuid: transfer_uuid, amount: amount} = command

    if is_number(amount) and amount > 0 do
      event = %MoneyWithdrawn{
        account_number: account_number,
        transfer_uuid: transfer_uuid,
        amount: amount,
        balance: balance - amount
      }

      {:ok, event}
    else
      {:error, :invalid_amount}
    end
  end

  defp check_balance(%BankAccount{balance: balance}) when balance < 0,
    do: {:error, :insufficient_funds_available}

  defp check_balance(%BankAccount{}), do: []
end
