defmodule Commanded.ExampleDomain.BankAccount do
  use EventSourced.Entity, fields: [account_number: nil, balance: 0]

  alias Commanded.ExampleDomain.BankAccount

  defmodule Commands do
    defmodule OpenAccount do
      defstruct aggregate: BankAccount, aggregate_uuid: UUID.uuid4, account_number: nil, initial_balance: nil
    end

    defmodule DepositMoney do
      defstruct aggregate: BankAccount, aggregate_uuid: nil, amount: nil
    end
  end

  defmodule Events do
    defmodule BankAccountOpened do
      defstruct account_number: nil, initial_balance: nil
    end

    defmodule MoneyDeposited do
      defstruct amount: nil, balance: nil
    end

    defmodule MoneyWithdrawn do
      defstruct amount: nil, balance: nil
    end
  end

  alias Events.{BankAccountOpened,MoneyDeposited,MoneyWithdrawn}

  def open_account(%BankAccount{} = account, account_number, initial_balance) when initial_balance > 0 do
    account
    |> apply(%BankAccountOpened{account_number: account_number, initial_balance: initial_balance})
  end

  def deposit(%BankAccount{} = account, amount) when amount > 0 do
    balance = account.state.balance + amount

    account
    |> apply(%MoneyDeposited{amount: amount, balance: balance})
  end

  def withdraw(%BankAccount{} = account, amount) when amount > 0 do
    balance = account.state.balance - amount

    account
    |> apply(%MoneyWithdrawn{amount: amount, balance: balance})
  end

  def apply(%BankAccount{} = account, %BankAccountOpened{} = account_opened) do
    apply_event(account, account_opened, fn state -> %{state |
      account_number: account_opened.account_number,
      balance: account_opened.initial_balance
    } end)
  end

  def apply(%BankAccount{} = account, %MoneyDeposited{} = money_deposited) do
    apply_event(account, money_deposited, fn state -> %{state |
      balance: money_deposited.balance
    } end)
  end

  def apply(%BankAccount{} = account, %MoneyWithdrawn{} = money_withdrawn) do
    apply_event(account, money_withdrawn, fn state -> %{state |
      balance: money_withdrawn.balance
    } end)
  end
end
