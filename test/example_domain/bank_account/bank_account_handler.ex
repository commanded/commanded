defmodule Commanded.ExampleDomain.BankAccount.BankAccountHandler do
  @moduledoc false

  use Commanded.Event.Handler,
    application: Commanded.ExampleDomain.BankApp,
    name: __MODULE__,
    start_from: :origin

  alias Commanded.ExampleDomain.BankAccount.Events.BankAccountOpened

  def init do
    case Agent.start_link(fn -> %{prefix: "", accounts: []} end, name: __MODULE__) do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> :ok
      _ -> {:error, :unable_to_start}
    end
  end

  def before_reset do
    Agent.update(__MODULE__, fn state -> %{state | accounts: []} end)
  end

  def handle(%BankAccountOpened{} = event, _metadata) do
    %BankAccountOpened{account_number: account_number} = event

    Agent.update(__MODULE__, fn %{prefix: prefix, accounts: accounts} = state ->
      %{state | accounts: accounts ++ [prefix <> account_number]}
    end)
  end

  def subscribed? do
    try do
      Agent.get(__MODULE__, fn _ -> true end)
    catch
      :exit, _reason -> false
    end
  end

  def change_prefix(prefix) do
    try do
      Agent.update(__MODULE__, fn s -> %{s | prefix: prefix} end)
    catch
      :exit, _reason ->
        nil
    end
  end

  def current_accounts do
    try do
      Agent.get(__MODULE__, fn %{accounts: accounts} -> accounts end)
    catch
      # catch agent not started exits, return `nil` balance
      :exit, _reason ->
        nil
    end
  end
end
