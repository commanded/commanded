defmodule Commanded.Aggregate.Multi.BankAccount do
  defstruct account_number: nil,
            balance: 0,
            state: nil

  alias Commanded.Aggregate.Multi
  alias Commanded.Aggregate.Multi.BankAccount

  defmodule Commands do
    defmodule(OpenAccount, do: defstruct([:account_number, :initial_balance]))
    defmodule(WithdrawMoney, do: defstruct([:account_number, :transfer_uuid, :amount]))
  end

  defmodule Events do
    defmodule(BankAccountOpened, do: defstruct([:account_number, :balance]))
    defmodule(MoneyWithdrawn, do: defstruct([:account_number, :transfer_uuid, :amount, :balance]))
  end

  alias Commands.{OpenAccount, WithdrawMoney}
  alias Events.{BankAccountOpened, MoneyWithdrawn}

  def execute(
        %BankAccount{state: nil},
        %OpenAccount{account_number: account_number, initial_balance: initial_balance}
      )
      when is_number(initial_balance) and initial_balance > 0 do
    %BankAccountOpened{account_number: account_number, balance: initial_balance}
  end

  def execute(
        %BankAccount{state: :active} = account,
        %WithdrawMoney{amount: amount}
      )
      when is_number(amount) and amount > 0 do
    account
    |> Multi.new()
    |> Multi.execute(&withdraw_money(&1, amount))
    |> Multi.execute(&check_balance/1)
  end

  # State mutators

  def apply(
        %BankAccount{} = state,
        %BankAccountOpened{account_number: account_number, balance: balance}
      ) do
    %BankAccount{state | account_number: account_number, balance: balance, state: :active}
  end

  def apply(%BankAccount{} = state, %MoneyWithdrawn{balance: balance}),
    do: %BankAccount{state | balance: balance}

  # private helpers

  defp withdraw_money(%BankAccount{account_number: account_number, balance: balance}, amount) do
    %MoneyWithdrawn{
      account_number: account_number,
      amount: amount,
      balance: balance - amount
    }
  end

  defp check_balance(%BankAccount{balance: balance})
       when balance < 0 do
    {:error, :insufficient_funds_available}
  end

  defp check_balance(%BankAccount{}), do: []
end
