defmodule Commanded.Aggregate.Multi.BankAccount do
  defstruct [:account_number, :status, balance: 0]

  alias Commanded.Aggregate.Multi
  alias Commanded.Aggregate.Multi.BankAccount

  defmodule Commands do
    defmodule OpenAccount do
      defstruct [:account_number, :initial_balance]
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

    defmodule MoneyWithdrawn do
      @derive Jason.Encoder
      defstruct [:account_number, :transfer_uuid, :amount, :balance]
    end
  end

  alias Commands.{OpenAccount, WithdrawMoney}
  alias Events.{BankAccountOpened, MoneyWithdrawn}

  # Public command functions

  def execute(%BankAccount{status: nil}, %OpenAccount{initial_balance: initial_balance} = command)
      when is_number(initial_balance) and initial_balance > 0 do
    %OpenAccount{account_number: account_number} = command

    %BankAccountOpened{account_number: account_number, balance: initial_balance}
  end

  def execute(%BankAccount{status: :active} = account, %WithdrawMoney{amount: amount})
      when is_number(amount) and amount > 0 do
    account
    |> Multi.new()
    |> Multi.execute(&withdraw_money(&1, amount))
    |> Multi.execute(&check_balance/1)
  end

  # State mutators

  def apply(%BankAccount{} = state, %BankAccountOpened{} = event) do
    %BankAccountOpened{account_number: account_number, balance: balance} = event

    %BankAccount{state | account_number: account_number, balance: balance, status: :active}
  end

  def apply(%BankAccount{} = state, %MoneyWithdrawn{} = event) do
    %MoneyWithdrawn{balance: balance} = event

    %BankAccount{state | balance: balance}
  end

  # Private helpers

  defp withdraw_money(%BankAccount{} = state, amount) do
    %BankAccount{account_number: account_number, balance: balance} = state

    %MoneyWithdrawn{
      account_number: account_number,
      amount: amount,
      balance: balance - amount
    }
  end

  defp check_balance(%BankAccount{balance: balance}) when balance < 0 do
    {:error, :insufficient_funds_available}
  end

  defp check_balance(%BankAccount{}), do: []
end
