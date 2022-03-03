defmodule Commanded.ExampleDomain.BankAccount do
  @moduledoc false

  @derive Jason.Encoder
  defstruct [:account_number, :state, balance: 0]

  alias Commanded.ExampleDomain.BankAccount

  defmodule Commands do
    defmodule OpenAccount do
      defstruct [:account_number, :initial_balance]
    end

    defmodule DepositMoney do
      defstruct [:account_number, :transfer_uuid, :amount]
    end

    defmodule WithdrawMoney do
      defstruct [:account_number, :transfer_uuid, :amount]
    end

    defmodule CloseAccount do
      defstruct [:account_number]
    end
  end

  defmodule Events do
    defmodule BankAccountOpened do
      @derive Jason.Encoder
      defstruct [:account_number, :initial_balance]
    end

    defmodule MoneyDeposited do
      @derive Jason.Encoder
      defstruct [:account_number, :transfer_uuid, :amount, :balance]
    end

    defmodule MoneyWithdrawn do
      @derive Jason.Encoder
      defstruct [:account_number, :transfer_uuid, :amount, :balance]
    end

    defmodule AccountOverdrawn do
      @derive Jason.Encoder
      defstruct [:account_number, :balance]
    end

    defmodule BankAccountClosed do
      @derive Jason.Encoder
      defstruct [:account_number]
    end
  end

  alias Commands.{CloseAccount, DepositMoney, OpenAccount, WithdrawMoney}

  alias Events.{
    AccountOverdrawn,
    BankAccountClosed,
    BankAccountOpened,
    MoneyDeposited,
    MoneyWithdrawn
  }

  def open_account(
        %BankAccount{state: nil},
        %OpenAccount{initial_balance: initial_balance} = command
      )
      when is_number(initial_balance) and initial_balance > 0 do
    %OpenAccount{account_number: account_number} = command

    %BankAccountOpened{account_number: account_number, initial_balance: initial_balance}
  end

  def open_account(%BankAccount{state: nil}, %OpenAccount{}),
    do: {:error, :invalid_initial_balance}

  def deposit(
        %BankAccount{state: :active} = account,
        %DepositMoney{amount: amount} = command
      )
      when is_number(amount) and amount > 0 do
    %BankAccount{balance: balance} = account
    %DepositMoney{account_number: account_number, transfer_uuid: transfer_uuid} = command

    balance = balance + amount

    %MoneyDeposited{
      account_number: account_number,
      transfer_uuid: transfer_uuid,
      amount: amount,
      balance: balance
    }
  end

  def withdraw(
        %BankAccount{state: :active} = account,
        %WithdrawMoney{amount: amount} = command
      )
      when is_number(amount) and amount > 0 do
    %BankAccount{balance: balance} = account
    %WithdrawMoney{account_number: account_number, transfer_uuid: transfer_uuid} = command

    case balance - amount do
      balance when balance < 0 ->
        [
          %MoneyWithdrawn{
            account_number: account_number,
            transfer_uuid: transfer_uuid,
            amount: amount,
            balance: balance
          },
          %AccountOverdrawn{account_number: account_number, balance: balance}
        ]

      balance ->
        %MoneyWithdrawn{
          account_number: account_number,
          transfer_uuid: transfer_uuid,
          amount: amount,
          balance: balance
        }
    end
  end

  def close_account(%BankAccount{state: :closed}, %CloseAccount{}) do
    []
  end

  def close_account(%BankAccount{state: :active}, %CloseAccount{account_number: account_number}) do
    %BankAccountClosed{account_number: account_number}
  end

  # State mutators

  def apply(%BankAccount{} = state, %BankAccountOpened{} = event) do
    %BankAccountOpened{account_number: account_number, initial_balance: initial_balance} = event

    %BankAccount{state | account_number: account_number, balance: initial_balance, state: :active}
  end

  def apply(%BankAccount{} = state, %MoneyDeposited{balance: balance}),
    do: %BankAccount{state | balance: balance}

  def apply(%BankAccount{} = state, %MoneyWithdrawn{balance: balance}),
    do: %BankAccount{state | balance: balance}

  def apply(%BankAccount{} = state, %AccountOverdrawn{}), do: state

  def apply(%BankAccount{} = state, %BankAccountClosed{}) do
    %BankAccount{state | state: :closed}
  end
end
