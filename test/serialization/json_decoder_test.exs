defmodule Commanded.Serialization.JsonDecoderTest do
	use ExUnit.Case
	doctest Commanded.Serialization.JsonDecoder

  alias Commanded.Serialization.{JsonSerializer,JsonDecoder}

  defmodule ExampleEvent do
    defstruct [:name, :date]
  end

  defimpl JsonDecoder, for: ExampleEvent do
    @doc """
    Parse the date included in the event
    """
    def decode(%ExampleEvent{date: date} = event) do
      %ExampleEvent{event |
        date: NaiveDateTime.from_iso8601!(date)
      }
    end
  end

  @serialized_event_json "{\"name\":\"Ben\",\"date\":\"2016-09-20T20:01:02\"}"

  test "should serialize value to JSON" do
    event = %ExampleEvent{name: "Ben", date: ~N[2016-09-20 20:01:02]}

    assert JsonSerializer.serialize(event) == @serialized_event_json
  end

  test "should allow decoding of deserialized value from JSON" do
    event = %ExampleEvent{name: "Ben", date: ~N[2016-09-20 20:01:02]}
    type = Atom.to_string(event.__struct__)

    assert JsonSerializer.deserialize(@serialized_event_json, type: type) == event
  end
end
