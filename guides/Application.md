# Application

Commanded allows you to define, supervise and start your own application module. To use Commanded you must create at least one application module. You may also create multiple apps which will run independently and use their own configured event stores.

The application expects at least an `:otp_app` option to be specified. It should point to an OTP application that has the application configuration.

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
config :my_app, MyApp.Application
  event_store: [
    adapter: Commanded.EventStore.Adapters.EventStore,
    event_store: MyApp.EventStore
  ],
  pub_sub: :local,
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
