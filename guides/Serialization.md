# Serialization

JSON serialization can be used for event and snapshot data.

To enable JSON serialization with the included `Commanded.Serialization.JsonSerializer` module add `poison` to your deps

    ```elixir
    def deps do
      [{:poison, "~> 3.1 or ~> 4.0"}]
    end
    ```

The `Commanded.Serialization.JsonSerializer` module provides an extension point to allow additional decoding of the deserialized value. This can be used for parsing data into valid structures, such as date/time parsing from a string.

The example event below has an implementation of the `Commanded.Serialization.JsonDecoder` protocol to parse the date into a `NaiveDateTime` struct.

```elixir
defmodule ExampleEvent do
  defstruct [:name, :date]
end

defimpl Commanded.Serialization.JsonDecoder, for: ExampleEvent do
  @doc """
  Parse the date included in the event
  """
  def decode(%ExampleEvent{date: date} = event) do
    %ExampleEvent{event |
      date: NaiveDateTime.from_iso8601!(date)
    }
  end
end
```

[Poison](https://github.com/devinus/poison), a pure Elixir JSON library, is used for the actual serialization. It provides an extension point if you need to manually encode your event by using the `Poison.Encoder` protocol:

```elixir
defimpl Poison.Encoder, for: Person do
  def encode(%{name: name, age: age}, options) do
    Poison.Encoder.BitString.encode("#{name} (#{age})", options)
  end
end
```

For maximum performance, make sure you `@derive [Poison.Encoder]` for any struct you plan on encoding.

```elixir
defmodule ExampleEvent do
  @derive [Poison.Encoder]
  defstruct [:name, :date]
end
```

## Using an alternative serialization format

You can implement the `Commanded.EventStore.Serializer` behaviour to use an alternative serialization format if preferred.

Configure your own serializer in `config/config.exs` for the event store you are using.

- Elixir EventStore:

    ```elixir
    config :eventstore, EventStore.Storage,
      serializer: MyApp.MessagePackSerializer,
      # ...
    ```

- Greg Young's Event Store:

    ```elixir
    config :commanded_extreme_adapter,
      serializer: Commanded.Serialization.JsonSerializer,
      # ...
    ```

You *should not* change serialization format once your app has been deployed to production since Commanded will not be able to deserialize any existing events or snapshot data. In this scenario, to change serialization format you would need to also migrate your event store to the new format.
