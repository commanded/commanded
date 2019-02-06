# Serialization

JSON serialization can be used for event data, and aggregate and process manager snapshot data.

To enable JSON serialization with the included `Commanded.Serialization.JsonSerializer` module add `jason` to your deps:

    ```elixir
    def deps do
      [{:jason, "~> 1.1"}]
    end
    ```

The `Commanded.Serialization.JsonSerializer` module provides an extension point to allow additional decoding of the deserialized value. This can be used for parsing data into valid structures, such as date/time parsing from a string.

The example event below has an implementation of the `Commanded.Serialization.JsonDecoder` protocol to parse the date into a `DateTime` struct.

```elixir
defmodule ExampleEvent do
  @derive Jason.Encoder
  defstruct [:name, :date]
end

defimpl Commanded.Serialization.JsonDecoder, for: ExampleEvent do
  @doc """
  Parse the date included in the event.
  """
  def decode(%ExampleEvent{date: date} = event) do
    {:ok, dt, _} = DateTime.from_iso8601(date)
    %ExampleEvent{event | date: dt}
  end
end
```

[Jason](https://hex.pm/packages/jason), a pure Elixir JSON library, is used for the actual serialization. It provides an extension point if you need to manually encode your event by using the `Jason.Encoder` protocol:

```elixir
defimpl Jason.Encoder, for: Person do
  def encode(%{name: name, age: age}, opts) do
    Jason.Encode.string("#{name} (#{age})", options)
  end
end
```

Make sure you `@derive Jason.Encoder` for any struct you plan on encoding.

```elixir
defmodule ExampleEvent do
  @derive Jason.Encoder
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
