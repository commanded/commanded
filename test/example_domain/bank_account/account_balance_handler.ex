defmodule Commanded.ExampleDomain.BankAccount.AccountBalanceHandler do
  @moduledoc false
  use Commanded.Event.Handler, name: __MODULE__

  alias Commanded.ExampleDomain.BankAccount.Events.{
    BankAccountOpened,
    MoneyDeposited,
    MoneyWithdrawn,
  }

  @agent_name {:global, __MODULE__}

  def init do
    with {:ok, _pid} <- Agent.start_link(fn -> 0 end, name: @agent_name) do
      :ok
    end
  end

  def handle(%BankAccountOpened{initial_balance: initial_balance}, _metadata) do
    Agent.update(@agent_name, fn _ -> initial_balance end)
  end

  def handle(%MoneyDeposited{balance: balance}, _metadata) do
    Agent.update(@agent_name, fn _ -> balance end)
  end

  def handle(%MoneyWithdrawn{balance: balance}, _metadata) do
    Agent.update(@agent_name, fn _ -> balance end)
  end

  def current_balance do
    Agent.get(@agent_name, fn balance -> balance end)
  end
end
