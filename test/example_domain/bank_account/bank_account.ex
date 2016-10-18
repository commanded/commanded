defmodule Commanded.ExampleDomain.BankAccount do
  use EventSourced.AggregateRoot, fields: [account_number: nil, balance: 0, is_active?: false]

  alias Commanded.ExampleDomain.BankAccount

  defmodule Commands do
    defmodule OpenAccount,        do: defstruct [:account_number, :initial_balance]
    defmodule DepositMoney,       do: defstruct [:account_number, :transfer_uuid, :amount]
    defmodule WithdrawMoney,      do: defstruct [:account_number, :transfer_uuid, :amount]
    defmodule CloseAccount,       do: defstruct [:account_number]
  end

  defmodule Events do
    defmodule BankAccountOpened,  do: defstruct [:account_number, :initial_balance]
    defmodule MoneyDeposited,     do: defstruct [:account_number, :transfer_uuid, :amount, :balance]
    defmodule MoneyWithdrawn,     do: defstruct [:account_number, :transfer_uuid, :amount, :balance]
    defmodule BankAccountClosed,  do: defstruct [:account_number]
  end

  alias Commands.{OpenAccount,DepositMoney,WithdrawMoney,CloseAccount}
  alias Events.{BankAccountOpened,MoneyDeposited,MoneyWithdrawn,BankAccountClosed}

  def open_account(%BankAccount{state: %{is_active?: true}}, %OpenAccount{}), do: {:error, :account_already_open}
  def open_account(%BankAccount{state: %{is_active?: false}} = account, %OpenAccount{account_number: account_number, initial_balance: initial_balance}) when is_number(initial_balance) and initial_balance > 0 do
    account =
      account
      |> update(%BankAccountOpened{account_number: account_number, initial_balance: initial_balance})

    {:ok, account}
  end

  def deposit(%BankAccount{} = account, %DepositMoney{account_number: account_number, transfer_uuid: transfer_uuid, amount: amount}) when is_number(amount) and amount > 0 do
    balance = account.state.balance + amount

    account =
      account
      |> update(%MoneyDeposited{account_number: account_number, transfer_uuid: transfer_uuid, amount: amount, balance: balance})

    {:ok, account}
  end

  def withdraw(%BankAccount{} = account, %WithdrawMoney{account_number: account_number, transfer_uuid: transfer_uuid, amount: amount}) when is_number(amount) and amount > 0 do
    balance = account.state.balance - amount

    account =
      account
      |> update(%MoneyWithdrawn{account_number: account_number, transfer_uuid: transfer_uuid, amount: amount, balance: balance})

    {:ok, account}
  end

  def close_account(%BankAccount{state: %{is_active?: false}}, %OpenAccount{}), do: {:error, :account_already_closed}
  def close_account(%BankAccount{state: %{is_active?: true}} = account, %CloseAccount{account_number: account_number}) do
    account =
      account
      |> update(%BankAccountClosed{account_number: account_number})

    {:ok, account}
  end

  # state mutatators

  def apply(%BankAccount.State{} = state, %BankAccountOpened{} = account_opened) do
    %BankAccount.State{state |
      account_number: account_opened.account_number,
      balance: account_opened.initial_balance,
      is_active?: true,
    }
  end

  def apply(%BankAccount.State{} = state, %MoneyDeposited{} = money_deposited) do
    %BankAccount.State{state |
      balance: money_deposited.balance
    }
  end

  def apply(%BankAccount.State{} = state, %MoneyWithdrawn{} = money_withdrawn) do
    %BankAccount.State{state |
      balance: money_withdrawn.balance
    }
  end

  def apply(%BankAccount.State{} = state, %BankAccountClosed{}) do
    %BankAccount.State{state |
      is_active?: false,
    }
  end
end
