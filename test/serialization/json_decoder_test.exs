defmodule Commanded.Serialization.JsonDecoderTest do
  use ExUnit.Case

  alias Commanded.Serialization.JsonSerializer
  alias Commanded.Serialization.JsonDecoder

  defmodule ExampleEvent do
    @derive Jason.Encoder
    defstruct [:name, :date]
  end

  defimpl JsonDecoder, for: ExampleEvent do
    @doc """
    Parse the date included in the event.
    """
    def decode(%ExampleEvent{date: date} = event) do
      %ExampleEvent{event | date: NaiveDateTime.from_iso8601!(date)}
    end
  end

  @serialized_event_json "{\"date\":\"2016-09-20T20:01:02\",\"name\":\"Ben\"}"

  test "should serialize value to JSON" do
    event = %ExampleEvent{name: "Ben", date: ~N[2016-09-20 20:01:02]}

    assert JsonSerializer.serialize(event) == @serialized_event_json
  end

  test "should allow decoding of deserialized value from JSON" do
    event = %ExampleEvent{name: "Ben", date: ~N[2016-09-20 20:01:02]}
    type = Atom.to_string(event.__struct__)

    assert JsonSerializer.deserialize(@serialized_event_json, type: type) == event
  end

  defmodule ParentEvent do
    @derive Jason.Encoder
    defstruct [:children]

    defmodule Child do
      @derive Jason.Encoder
      defstruct [:name]
    end

    defimpl JsonDecoder do
      @doc """
      Parse the children structs.
      """
      def decode(%ParentEvent{children: children} = event) do
        %ParentEvent{event | children: Enum.map(children, &struct(Child, &1))}
      end
    end
  end

  test "should allow decoding of nested JSON data" do
    event = %ParentEvent{
      children: [
        %ParentEvent.Child{name: "child1"},
        %ParentEvent.Child{name: "child2"},
        %ParentEvent.Child{name: "child3"}
      ]
    }

    type = "#{__MODULE__}.ParentEvent"

    assert event |> JsonSerializer.serialize() |> JsonSerializer.deserialize(type: type) == event
  end
end
