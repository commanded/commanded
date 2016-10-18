defmodule Commanded.ExampleDomain.BankAccount do
  use EventSourced.AggregateRoot, fields: [account_number: nil, balance: 0, is_active?: false]

  alias Commanded.ExampleDomain.BankAccount

  defmodule Commands do
    defmodule OpenAccount do
      defstruct account_number: nil, initial_balance: nil
    end

    defmodule DepositMoney do
      defstruct account_number: nil, transfer_uuid: nil, amount: nil
    end

    defmodule WithdrawMoney do
      defstruct account_number: nil, transfer_uuid: nil, amount: nil
    end
  end

  defmodule Events do
    defmodule BankAccountOpened do
      defstruct account_number: nil, initial_balance: nil
    end

    defmodule MoneyDeposited do
      defstruct account_number: nil, transfer_uuid: nil, amount: nil, balance: nil
    end

    defmodule MoneyWithdrawn do
      defstruct account_number: nil, transfer_uuid: nil, amount: nil, balance: nil
    end
  end

  alias Commands.{OpenAccount,DepositMoney,WithdrawMoney}
  alias Events.{BankAccountOpened,MoneyDeposited,MoneyWithdrawn}

  def open_account(%BankAccount{state: %{is_active?: true}}, %OpenAccount{}) do
    {:error, :account_already_open}
  end

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
end
