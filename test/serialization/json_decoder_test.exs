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

  @serialized_event_json "{\"datetime\":\"2016-09-20T20:01:02Z\",\"name\":\"Ben\"}"

  test "should serialize value to JSON" do
    {:ok, dt, _} = DateTime.from_iso8601("2016-09-20 20:01:02Z")
    event = %ExampleEvent{name: "Ben", datetime: dt}

    assert JsonSerializer.serialize(event) == @serialized_event_json
  end

  test "should allow decoding of deserialized value from JSON" do
    {:ok, dt, _} = DateTime.from_iso8601("2016-09-20 20:01:02Z")

    event = %ExampleEvent{name: "Ben", datetime: dt}
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
