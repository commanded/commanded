defmodule Commanded.Aggregates.BankAccountLifespan do
  @moduledoc false

  @behaviour Commanded.Aggregates.AggregateLifespan

  alias Commanded.ExampleDomain.BankAccount.Events.{
    BankAccountClosed,
    BankAccountOpened,
    MoneyDeposited
  }

  def after_event(%BankAccountOpened{}), do: 25
  def after_event(%MoneyDeposited{}), do: 50
  def after_event(%BankAccountClosed{}), do: :stop
  def after_event(_event), do: :infinity
end
