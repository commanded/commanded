defmodule Commanded.Serialization.JsonSerializerTest do
	use ExUnit.Case
	doctest Commanded.Serialization.JsonSerializer

  alias Commanded.Serialization.JsonSerializer
  alias Commanded.Serialization.JsonSerializer.EventName
  alias Commanded.ExampleDomain.BankAccount.Events.{BankAccountOpened}

  defmodule NamedEvent do
    use EventName, "named-event"

    defstruct data: nil
  end

  defmodule AnotherNamedEvent do
    use EventName, "another-named-event"

    defstruct data: nil
  end

  @serialized_event_json "{\"initial_balance\":1000,\"account_number\":\"ACC123\"}"
  
	test "should serialize event to JSON" do
    account_opened = %BankAccountOpened{account_number: "ACC123", initial_balance: 1_000}

    assert JsonSerializer.serialize(account_opened) == @serialized_event_json
  end

  test "should deserialize event from JSON" do
    account_opened = %BankAccountOpened{account_number: "ACC123", initial_balance: 1_000}
    type = Atom.to_string(account_opened.__struct__)

    assert JsonSerializer.deserialize(@serialized_event_json, type: type) == account_opened
  end

  test "should map to event name specified by 'use EventName'" do
    assert "named-event" == JsonSerializer.to_event_name(NamedEvent)
    assert "another-named-event" == JsonSerializer.to_event_name(AnotherNamedEvent)
  end

  test "should deserialize to event type which is specifying the event name by 'use EventName'" do
    assert %NamedEvent{data: "data"} == JsonSerializer.deserialize("{\"data\": \"data\"}", type: "named-event")
    assert %AnotherNamedEvent{data: "data"} == JsonSerializer.deserialize("{\"data\": \"data\"}", type: "another-named-event")
  end
end
