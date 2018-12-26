defmodule Commanded.ExampleDomain.BankAccount do
  @moduledoc false
  @derive Jason.Encoder
  defstruct account_number: nil,
            balance: 0,
            state: nil

  alias Commanded.ExampleDomain.BankAccount

  defmodule Commands do
    defmodule OpenAccount do
      @derive Jason.Encoder
      defstruct([:account_number, :initial_balance])
    end

    defmodule DepositMoney do
      @derive Jason.Encoder
      defstruct([:account_number, :transfer_uuid, :amount])
    end

    defmodule WithdrawMoney do
      @derive Jason.Encoder
      defstruct([:account_number, :transfer_uuid, :amount])
    end

    defmodule CloseAccount do
      @derive Jason.Encoder
      defstruct([:account_number])
    end
  end

  defmodule Events do
    defmodule BankAccountOpened do
      @derive Jason.Encoder
      defstruct([:account_number, :initial_balance])
    end

    defmodule MoneyDeposited do
      @derive Jason.Encoder
      defstruct([:account_number, :transfer_uuid, :amount, :balance])
    end

    defmodule MoneyWithdrawn do
      @derive Jason.Encoder
      defstruct([:account_number, :transfer_uuid, :amount, :balance])
    end

    defmodule AccountOverdrawn do
      @derive Jason.Encoder
      defstruct([:account_number, :balance])
    end

    defmodule BankAccountClosed do
      @derive Jason.Encoder
      defstruct([:account_number])
    end
  end

  alias Commands.{OpenAccount, DepositMoney, WithdrawMoney, CloseAccount}

  alias Events.{
    BankAccountOpened,
    MoneyDeposited,
    MoneyWithdrawn,
    AccountOverdrawn,
    BankAccountClosed
  }

  def open_account(%BankAccount{state: nil}, %OpenAccount{initial_balance: "clearly invalid"}) do
    {:error, :invalid_initial_balance}
  end

  def open_account(%BankAccount{state: nil}, %OpenAccount{
        account_number: account_number,
        initial_balance: initial_balance
      })
      when is_number(initial_balance) and initial_balance > 0 do
    %BankAccountOpened{account_number: account_number, initial_balance: initial_balance}
  end

  def deposit(%BankAccount{state: :active, balance: balance}, %DepositMoney{
        account_number: account_number,
        transfer_uuid: transfer_uuid,
        amount: amount
      })
      when is_number(amount) and amount > 0 do
    balance = balance + amount

    %MoneyDeposited{
      account_number: account_number,
      transfer_uuid: transfer_uuid,
      amount: amount,
      balance: balance
    }
  end

  def withdraw(%BankAccount{state: :active, balance: balance}, %WithdrawMoney{
        account_number: account_number,
        transfer_uuid: transfer_uuid,
        amount: amount
      })
      when is_number(amount) and amount > 0 do
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

  def apply(%BankAccount{} = state, %BankAccountOpened{
        account_number: account_number,
        initial_balance: initial_balance
      }) do
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
