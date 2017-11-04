defmodule Commanded.Aggregates.BankAccountLifespan do
  @moduledoc false
  @behaviour Commanded.Aggregates.AggregateLifespan

  alias Commanded.ExampleDomain.BankAccount.Commands.{
    OpenAccount,
    DepositMoney,
  }

  def after_command(%OpenAccount{}), do: 5
  def after_command(%DepositMoney{}), do: 20
  def after_command(_), do: :infinity
end
