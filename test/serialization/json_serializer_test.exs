defmodule Commanded.Serialization.JsonSerializerTest do
  use ExUnit.Case

  alias Commanded.Serialization.JsonSerializer
  alias Commanded.ExampleDomain.BankAccount.Events.BankAccountOpened

  @serialized_event_json "{\"account_number\":\"ACC123\",\"initial_balance\":1000}"

  test "should serialize event to JSON" do
    account_opened = %BankAccountOpened{account_number: "ACC123", initial_balance: 1_000}

    assert JsonSerializer.serialize(account_opened) == @serialized_event_json
  end

  test "should deserialize event from JSON" do
    account_opened = %BankAccountOpened{account_number: "ACC123", initial_balance: 1_000}
    type = Atom.to_string(account_opened.__struct__)

    assert JsonSerializer.deserialize(@serialized_event_json, type: type) == account_opened
  end

  defmodule(NamedEvent, do: defstruct(data: nil))
  defmodule(AnotherNamedEvent, do: defstruct(data: nil))

  test "should deserialize to event type which is specifying the module name" do
    assert %NamedEvent{data: "data"} ==
             JsonSerializer.deserialize("{\"data\": \"data\"}",
               type: "Elixir.Commanded.Serialization.JsonSerializerTest.NamedEvent"
             )

    assert %AnotherNamedEvent{data: "data"} ==
             JsonSerializer.deserialize("{\"data\": \"data\"}",
               type: "Elixir.Commanded.Serialization.JsonSerializerTest.AnotherNamedEvent"
             )
  end
end
