defmodule Commanded.ExampleDomain.BankAccount.AccountBalanceHandler do
  @moduledoc false

  use Commanded.Event.Handler,
    application: Commanded.ExampleDomain.BankApp,
    name: __MODULE__

  alias Commanded.ExampleDomain.BankAccount.Events.BankAccountOpened
  alias Commanded.ExampleDomain.BankAccount.Events.MoneyDeposited
  alias Commanded.ExampleDomain.BankAccount.Events.MoneyWithdrawn

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

  def subscribed? do
    try do
      Agent.get(__MODULE__, fn _ -> true end)
    catch
      :exit, _reason -> false
    end
  end

  def current_balance do
    try do
      Agent.get(__MODULE__, fn balance -> balance end)
    catch
      # Catch agent not started exits, return `nil` balance
      :exit, _reason ->
        nil
    end
  end
end
