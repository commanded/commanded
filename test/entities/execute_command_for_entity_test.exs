defmodule Commanded.Entities.ExecuteCommandForEntityTest do
  use ExUnit.Case
  doctest Commanded.Entities.Entity

  alias Commanded.Entities.{Registry,Entity}
  alias Commanded.ExampleDomain.{BankAccount,OpenAccountHandler,DepositMoneyHandler}
  alias Commanded.ExampleDomain.BankAccount.Commands.{OpenAccount,DepositMoney}
  alias Commanded.Helpers

  setup do
    {:ok, _} = Registry.start_link
    :ok
  end

  test "execute command against an entity" do
    entity_uuid = UUID.uuid4

    {:ok, entity} = Registry.open_entity(BankAccount, entity_uuid)

    :ok = Entity.execute(entity, %OpenAccount{account_number: "ACC123", initial_balance: 1_000}, OpenAccountHandler)

    Helpers.Process.shutdown(entity)

    # reload entity to fetch persisted events from event store and rebuild state by applying saved events
    {:ok, entity} = Registry.open_entity(BankAccount, entity_uuid)

    bank_account = Entity.state(entity)

    assert bank_account.state.account_number == "ACC123"
    assert bank_account.state.balance == 1_000
    assert length(bank_account.events) == 0
    assert bank_account.id == entity_uuid
    assert bank_account.version == 1
  end

  test "execute command against an entity with concurrency error should reload events and retry command" do
    entity_uuid = UUID.uuid4

    {:ok, entity} = Registry.open_entity(BankAccount, entity_uuid)

    # write an event to the entity's stream, bypassing the entity process (simulate concurrency error)
    EventStore.append_to_stream(entity_uuid, 0, [
      %EventStore.EventData{
        event_type: "Elixir.Commanded.ExampleDomain.BankAccount.Events.BankAccountOpened",
        headers: nil,
        payload: "{\"initial_balance\":1000,\"account_number\":\"ACC123\"}"
      }
    ])

    Entity.execute(entity, %DepositMoney{entity_id: entity_uuid, amount: 50}, DepositMoneyHandler)

    bank_account = Entity.state(entity)

    assert bank_account.state.account_number == "ACC123"
    assert bank_account.state.balance == 1_050
  end
end
