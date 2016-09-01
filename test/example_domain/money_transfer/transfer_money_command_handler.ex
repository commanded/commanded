defmodule Commanded.ExampleDomain.TransferMoneyHandler do
  alias Commanded.ExampleDomain.MoneyTransfer
  alias MoneyTransfer.Commands.{TransferMoney,ReverseMoneyTransfer}

  @behaviour Commanded.Commands.Handler

  def handle(%MoneyTransfer{} = aggregate, %TransferMoney{} = transfer_money) do
    aggregate
    |> MoneyTransfer.transfer_money(transfer_money)
  end

  def handle(%MoneyTransfer{} = aggregate, %ReverseMoneyTransfer{} = reverse_money_transfer) do
    aggregate
    |> MoneyTransfer.reverse_money_transfer(reverse_money_transfer)
  end
end
