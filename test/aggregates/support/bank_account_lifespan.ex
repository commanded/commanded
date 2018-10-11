defmodule Commanded.Aggregates.BankAccountLifespan do
  @moduledoc false

  @behaviour Commanded.Aggregates.AggregateLifespan

  alias Commanded.ExampleDomain.BankAccount.Events.{
    BankAccountClosed,
    BankAccountOpened,
    MoneyDeposited
  }

  alias Commanded.ExampleDomain.BankAccount.Commands.CloseAccount

  def after_command(%CloseAccount{}), do: :stop
  def after_command(_), do: 10

  def after_error(:invalid_initial_balance), do: 30

  def after_event(%BankAccountOpened{}), do: 25
  def after_event(%MoneyDeposited{}), do: 50
  def after_event(%BankAccountClosed{}), do: :stop
  def after_event(_event), do: :infinity
end
