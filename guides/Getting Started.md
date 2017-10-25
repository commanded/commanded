# Getting started

EventStore is [available in Hex](https://hex.pm/packages/eventstore) and can be installed as follows:

  1. Add eventstore to your list of dependencies in `mix.exs`:

      ```elixir    
      def deps do
        [{:eventstore, "~> 0.12"}]
      end
      ```

  2. Add an `eventstore` config entry containing the PostgreSQL database connection details to each environment's mix config file (e.g. `config/dev.exs`):

      ```elixir
      config :eventstore, EventStore.Storage,
        serializer: EventStore.TermSerializer,
        username: "postgres",
        password: "postgres",
        database: "eventstore_dev",
        hostname: "localhost",
        pool_size: 10,
        pool_overflow: 5
      ```

  The database connection pool configuration options are:

  - `:pool_size` - The number of connections (default: `10`).
  - `:pool_overflow` - The maximum number of overflow connections to start if all connections are checked out (default: `0`).

  3. Create the EventStore database and tables using the `mix` task:

      ```console
      $ mix event_store.create
      ```
