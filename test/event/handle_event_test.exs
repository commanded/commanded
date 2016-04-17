defmodule Commanded.Event.HandleEventTest do
	use ExUnit.Case
	doctest Commanded.Event.Handler

  alias Commanded.Entities.{Entity,Registry}
	alias Commanded.ExampleDomain.{BankAccount,AccountBalanceHandler}
	alias Commanded.ExampleDomain.BankAccount.Commands.{OpenAccount,DepositMoney}
	alias Commanded.ExampleDomain.BankAccount.Events.{BankAccountOpened,MoneyDeposited}
	alias Commanded.ExampleDomain.{OpenAccountHandler,DepositMoneyHandler}
  alias Commanded.Helpers.Wait

	setup do
		EventStore.Storage.reset!
		Commanded.Supervisor.start_link
    {:ok, _} = AccountBalanceHandler.start_link
		:ok
	end

	@tag :wip
	test "event handler is notified of events" do
		{:ok, handler} = Commanded.Event.Handler.start_link("account_balance", AccountBalanceHandler)

		entity_uuid = UUID.uuid4

		{:ok, entity} = Registry.open_entity(BankAccount, entity_uuid)

		:ok = Entity.execute(entity, %OpenAccount{account_number: "ACC123", initial_balance: 1_000}, OpenAccountHandler)
		:ok = Entity.execute(entity, %DepositMoney{amount: 50}, DepositMoneyHandler)

    Wait.until fn ->
      assert AccountBalanceHandler.current_balance == 1_050
    end
	end

	#test "should ignore already seen events"
  #test "should ignore uninterested events"
end
