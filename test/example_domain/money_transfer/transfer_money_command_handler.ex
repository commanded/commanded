defmodule Commanded.ExampleDomain.TransferMoneyHandler do
  @moduledoc false
  alias Commanded.ExampleDomain.MoneyTransfer
  alias MoneyTransfer.Commands.{TransferMoney}

  @behaviour Commanded.Commands.Handler

  def handle(%MoneyTransfer{} = aggregate, %TransferMoney{} = transfer_money) do
    aggregate
    |> MoneyTransfer.transfer_money(transfer_money)
  end
end
