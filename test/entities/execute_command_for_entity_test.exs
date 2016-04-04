defmodule Commanded.Entities.ExecuteCommandForEntityTest do
  use ExUnit.Case
  doctest Commanded.Entities.Entity

  alias Commanded.Entities.{Registry,Entity}
  alias Commanded.ExampleDomain.{BankAccount,OpenAccountHandler}
  alias Commanded.ExampleDomain.BankAccount.Commands.OpenAccount
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
end
