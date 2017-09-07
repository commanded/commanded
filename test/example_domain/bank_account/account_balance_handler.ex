defmodule Commanded.ExampleDomain.BankAccount.AccountBalanceHandler do
  use Commanded.Event.Handler, name: __MODULE__

  alias Commanded.ExampleDomain.BankAccount.Events.{
    BankAccountOpened,
    MoneyDeposited,
    MoneyWithdrawn,
  }

  def init do
    with {:ok, _pid} <- Agent.start_link(fn -> 0 end, name: __MODULE__) do
      :ok
    end
  end

  def handle(%BankAccountOpened{initial_balance: initial_balance}, _metadata) do
    Agent.update(__MODULE__, fn _ -> initial_balance end)
  end

  def handle(%MoneyDeposited{balance: balance}, _metadata) do
    Agent.update(__MODULE__, fn _ -> balance end)
  end

  def handle(%MoneyWithdrawn{balance: balance}, _metadata) do
    Agent.update(__MODULE__, fn _ -> balance end)
  end

  def current_balance do
    Agent.get(__MODULE__, fn balance -> balance end)
  end
end
