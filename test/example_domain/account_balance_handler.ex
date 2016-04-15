defmodule Commanded.ExampleDomain.AccountBalanceHandler do
  alias Commanded.ExampleDomain.BankAccount
  alias Commanded.ExampleDomain.BankAccount.Events.{BankAccountOpened,MoneyDeposited}

  def start_link do
    Agent.start_link(fn -> 0 end, name: __MODULE__)
  end

  def handle(%BankAccountOpened{initial_balance: initial_balance}) do
    Agent.update(__MODULE__, fn _ -> initial_balance end)
  end

  def handle(%MoneyDeposited{amount: amount}) do
    Agent.update(__MODULE__, fn balance -> balance + amount end)
  end

  def current_balance do
    Agent.get(__MODULE__, fn balance -> balance end)
  end
end
