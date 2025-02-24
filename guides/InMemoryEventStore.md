# In memory event store

Commanded provides an in-memory event store implementation, for **test use only**, in the module `Commanded.EventStore.Adapters.InMemory`. This is a transient event store without persistence.

### Configuration

Ensure you configure the in-memory adapter in your environment config file, `config/test.exs`:

```elixir
config :my_app, MyApp.App,
  event_store: [
    adapter: Commanded.EventStore.Adapters.InMemory,
    serializer: Commanded.Serialization.JsonSerializer
  ]
```

You may replace or omit the serializer configuration. By including it here we ensure events used by the tests can be successfully serialized and deserialized.

### Usage

#### ExUnit case template

You can use ExUnit's case template feature to restart the in-memory event store for each test run.

```elixir
defmodule InMemoryEventStoreCase do
  use ExUnit.CaseTemplate

  alias Commanded.EventStore.Adapters.InMemory

  setup do
    {:ok, _apps} = Application.ensure_all_started(:my_app)

    on_exit(fn ->
      :ok = Application.stop(:my_app)
    end)
  end
end
```

Replace both occurrences of `:my_app` in the above ExUnit case template with the name of your own application.

The reason why your app must be stopped and then started between resetting the event store is to ensure all application processes are restarted with their initial state to prevent state from one test affecting another.

Use the `InMemoryEventStoreCase` module within any test files that need to use the event store.

```elixir
defmodule ExampleTest do
  use InMemoryEventStoreCase

  # Define your tests here ...
end
```

#### Running your tests

Run `mix test` as usual to execute the tests using the in-memory event store.
