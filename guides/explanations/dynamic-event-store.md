# Dynamic event store

EventStore supports starting multiple instances, each with a unique name. This feature can be used to support multi-tenancy where each tenant's data is stored separately in its own Postgres schema.

## Example usage

Define an application which uses the `init/1` callback function to set the event store name and schema from config:

```elixir
defmodule MyApp.Application do
  use Commanded.Application,
    otp_app: :my_app,
    event_store: [
      adapter: Trogon.EventStore.Adapter.EventStore,
      event_store: MyApp.EventStore
    ]

  def init(config) do
    name = Keyword.fetch!(config, :name)

    {tenant, config} = Keyword.pop(config, :tenant)

    # Set dynamic event store name
    config = put_in(config, [:event_store, :name], Module.concat([name, EventStore])

    # Set event store prefix (Postgres schema)
    config = put_in(config, [:event_store, :prefix], Atom.to_string(tenant))

    {:ok, config}
  end
end
```

Start an application per tenant:

```elixir
for tenant <- [:tenant1, :tenant2, :tenant3] do
  {:ok, _pid} = MyApp.Application.start_link(name: tenant, tenant: tenant)
end
```

Each started application will use its own dynamically named EventStore and separate Postgres schema.
