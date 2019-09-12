defmodule Commanded.Commands.Composite.ExampleCompositeRouter do
  @moduledoc false

  use Commanded.Commands.CompositeRouter

  alias Commanded.Commands.Composite.BankAccountRouter
  alias Commanded.Commands.Composite.MoneyTransferRouter

  router(BankAccountRouter)
  router(MoneyTransferRouter)
end
