defmodule Commanded.ExampleDomain.AccountBalanceHandler do
  alias Commanded.ExampleDomain.BankAccount.Events.{BankAccountOpened,MoneyDeposited}

  @behaviour Commanded.Event.Handler

  def start_link do
    Agent.start_link(fn -> 0 end, name: __MODULE__)
  end

  def handle(%BankAccountOpened{initial_balance: initial_balance}, _metadata) do
    Agent.update(__MODULE__, fn _ -> initial_balance end)
  end

  def handle(%MoneyDeposited{balance: balance}, _metadata) do
    Agent.update(__MODULE__, fn _ -> balance end)
  end

  def handle(_event, _metadata) do
    # ignore any other events
    :ok
  end

  def current_balance do
    Agent.get(__MODULE__, fn balance -> balance end)
  end
end
