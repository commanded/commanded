# Application

Commanded allows you to define, supervise, and start your own application module. To use Commanded you must create at least one application. You can create multiple Commanded applications which will run independently, each using its own separately configured event store.

The application expects at least an `:otp_app` option to be specified. It should point to an OTP application containing the application's configuration.

For example, the application:

```elixir
defmodule MyApp.Application do
  use Commanded.Application, otp_app: :my_app

  router MyApp.Router
end
```

Could be configured with:

```elixir
# config/config.exs
config :my_app, MyApp.Application,
  event_store: [
    adapter: Commanded.EventStore.Adapters.EventStore,
    event_store: MyApp.EventStore
  ],
  pubsub: :local,
  registry: :local
```

Alternatively, you can include the event store, pubsub, and registry config when defining the application:

```elixir
defmodule MyApp.Application do
  use Commanded.Application,
    otp_app: :my_app,
    event_store: [
      adapter: Commanded.EventStore.Adapters.EventStore,
      event_store: MyApp.EventStore
    ],
    pubsub: :local,
    registry: :local

  router(MyApp.Router)
end
```

Finally, you can provide an optional `init/1` function to provide runtime configuration.

```elixir
defmodule MyApp.Application do
  use Commanded.Application, otp_app: :my_app

  def init(config) do
    {:ok, config}
  end
end
```

## Routing commands

A Commanded application is also a composite router. This provides the `router` macro allowing you to include one or more router modules for command dispatch.

```elixir
defmodule MyApp.Application do
  use Commanded.Application, otp_app: :my_app

  router(MyApp.Billing.Router)
  router(MyApp.Customers.Router)
  router(MyApp.Notifications.Router)
end
```

Once you have defined a router you can dispatch a command using the application module:

```elixir
:ok = MyApp.Application.dispatch(%RegisterCustomer{id: Commanded.UUID.uuid4(), name: "Ben"})
```
