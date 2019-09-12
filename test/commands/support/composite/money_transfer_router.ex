defmodule Commanded.Commands.Composite.MoneyTransferRouter do
  @moduledoc false

  use Commanded.Commands.Router

  alias Commanded.ExampleDomain.MoneyTransfer
  alias Commanded.ExampleDomain.MoneyTransfer.Commands.TransferMoney
  alias Commanded.ExampleDomain.TransferMoneyHandler

  identify MoneyTransfer, by: :transfer_uuid
  dispatch TransferMoney, to: TransferMoneyHandler, aggregate: MoneyTransfer
end
