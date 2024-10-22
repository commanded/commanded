defmodule Commanded.Serialization.JsonDecoderTest do
  use ExUnit.Case

  alias Commanded.Serialization.{JsonDecoder, JsonSerializer}

  defmodule ExampleEvent do
    @derive Jason.Encoder
    defstruct [:name, :datetime]
  end

  defimpl JsonDecoder, for: ExampleEvent do
    @doc """
    Parse the datetime included in the event.
    """
    def decode(%ExampleEvent{datetime: datetime} = event) do
      {:ok, dt, _} = DateTime.from_iso8601(datetime)
      %ExampleEvent{event | datetime: dt}
    end
  end

  test "should serialize value to JSON" do
    event = %ExampleEvent{name: "Ben", datetime: ~U[2024-10-22 00:00:00Z]}

    serialized = JsonSerializer.serialize(event)

    assert serialized =~ "\"datetime\":\"2024-10-22T00:00:00Z\""
    assert serialized =~ "\"name\":\"Ben\""
  end

  test "should allow decoding of deserialized value from JSON" do
    serialized = "{\"name\":\"Ben\",\"datetime\":\"2024-10-22T00:00:00Z\"}"

    type = Atom.to_string(ExampleEvent)
    deserialized = JsonSerializer.deserialize(serialized, type: type)

    event = %ExampleEvent{name: "Ben", datetime: ~U[2024-10-22 00:00:00Z]}
    assert deserialized == event
  end

  test "should round-trip serialization-deserialization" do
    event = %ExampleEvent{name: "Ben", datetime: ~U[2024-10-22 00:00:00Z]}
    type = Atom.to_string(ExampleEvent)

    deserialized = event |> JsonSerializer.serialize() |> JsonSerializer.deserialize(type: type)

    assert deserialized == event
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
