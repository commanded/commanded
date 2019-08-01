# Serialization

## Default JSON serializer

JSON serialization can be used for event data & metadata, and aggregate and process manager snapshots.

To enable JSON serialization with the included `Commanded.Serialization.JsonSerializer` module add `jason` to your deps:

```elixir
def deps do
  [{:jason, "~> 1.1"}]
end
```

[Jason](https://hex.pm/packages/jason), a pure Elixir JSON library, is used for the actual serialization.

You must derive the `Jason.Encoder` protocol for all structs you plan on encoding.

```elixir
defmodule ExampleEvent do
  @derive Jason.Encoder
  defstruct [:name, :datetime]
end
```

Jason provides an extension point if you need to manually encode your event by using the `Jason.Encoder` protocol:

```elixir
defimpl Jason.Encoder, for: Person do
  def encode(%{name: name, age: age}, opts) do
    Jason.Encode.string("#{name} (#{age})", options)
  end
end
```

## Configuring JSON serialization

JSON serialization configuration depends upon which event store you are using with Commanded. Configure the serializer in `config/config.exs`, or per environment, as follows.

- Postgres EventStore:

  ```elixir
  config :eventstore, EventStore.Storage,
    serializer: Commanded.Serialization.JsonSerializer
  ```

  You can also use the `EventStore.JsonSerializer` (`bytea` column type) and `EventStore.JsonbSerializer` (`jsonb` column type) serializers which are included in the EventStore library.

  ```elixir
  config :eventstore, EventStore.Storage,
    serializer: EventStore.JsonSerializer
  ```

  ```elixir
  config :eventstore, EventStore.Storage,
    serializer: EventStore.JsonbSerializer
  ```

  Note that the two EventStore serializers do not implement the `Commanded.Serialization.JsonSerializer` decoding protocol.

- Event Store:

  ```elixir
  config :commanded_extreme_adapter,
    serializer: Commanded.Serialization.JsonSerializer
  ```

- In-memory event store:

  ```elixir
  config :commanded, Commanded.EventStore.Adapters.InMemory,
    serializer: Commanded.Serialization.JsonSerializer
  ```

## Decoding event structs

The `Commanded.Serialization.JsonSerializer` module provides an extension point to allow additional decoding of the deserialized data. This can be used for parsing data into valid types, such as datetime parsing from a string.

The example event below has an implementation of the `Commanded.Serialization.JsonDecoder` protocol to parse the datetime into a `DateTime` struct.

```elixir
defmodule ExampleEvent do
  @derive Jason.Encoder
  defstruct [:name, :datetime]
end

defimpl Commanded.Serialization.JsonDecoder, for: ExampleEvent do
  @doc """
  Parse the datetime included in the event.
  """
  def decode(%ExampleEvent{datetime: datetime} = event) do
    {:ok, dt, _} = DateTime.from_iso8601(datetime)

    %ExampleEvent{event | datetime: dt}
  end
end
```

The above protocol is *only* supported by the `Commanded.Serialization.JsonSerializer` serializer.

## Using an alternative serialization format

You can implement your own serializer module to use an alternative serialization format if preferred.

Configure your own serializer in `config/config.exs` for the event store you are using.

- Postgres EventStore:

  ```elixir
  config :my_app, MyApp.EventStore, serializer: MyApp.MessagePackSerializer
  ```

- Event Store:

  ```elixir
  config :my_app, MyApp, serializer: MyApp.MessagePackSerializer
  ```

- In-memory event store:

  ```elixir
  config :my_app, MyApp,
    event_store: [
      adapter: Commanded.EventStore.Adapters.InMemory,
      serializer: MyApp.MessagePackSerializer
    ]
  ```

You *should not* change serialization format once your app has been deployed to production since Commanded will not be able to deserialize any existing events or snapshot data. In this scenario, to change serialization format you would need to also migrate your event store to the new format.

## Customising serialization

To implement custom serialization you could implement your own serializer which extends the behaviour of the existing `Commanded.Serialization.JsonSerializer` module.

The example below shows how you might compress the serialized data before storage and decompress during deserialization.

```elixir
defmodule CompressedJsonSerializer do
  def serialize(term) do
    term
    |> Commanded.Serialization.JsonSerializer.serialize()
    |> compress()
  end

  def deserialize(binary, config \\ []) do
    binary
    |> decompress()
    |> Commanded.Serialization.JsonSerializer.deserialize(config)    
  end

  defp compress(term), do: ...
  defp decompress(binary), do: ...
end
```
