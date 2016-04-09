defmodule Commanded.ExampleDomain.AccountBalanceHandler do
  alias Commanded.ExampleDomain.BankAccount
  alias Commanded.ExampleDomain.BankAccount.Events.{BankAccountOpened,MoneyDeposited}

  def handle(%BankAccountOpened{initial_balance: initial_balance}) do

  end

  def handle(%MoneyDeposited{amount: amount}) do

  end
end
