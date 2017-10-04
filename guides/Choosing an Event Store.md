# Choosing an event store

You must decide which event store to use with Commanded. You have a choice between two existing event store adapters:

- PostgreSQL-based Elixir [EventStore](https://github.com/slashdotdash/eventstore).

- Greg Young's [Event Store](https://geteventstore.com/).

There is also an [in-memory event store adapter](https://github.com/slashdotdash/commanded/wiki/In-memory-event-store) for *test use only*.

Want to use a different event store? Then you will need to [write your own event store provider](#writing-your-own-event-store-provider).

---

## PostgreSQL-based Elixir EventStore

[EventStore](https://github.com/slashdotdash/eventstore) is an open-source event store using PostgreSQL for persistence, implemented in Elixir.

1. Add `commanded_eventstore_adapter` to your list of dependencies in `mix.exs`:

    ```elixir
    def deps do
      [{:commanded_eventstore_adapter, "~> 0.1"}]
    end
    ```

2. Include `:eventstore` in the extra applications list in `mix.exs`:

    ```elixir
    def application do
      [
        extra_applications: [
          :logger,
          :eventstore,
        ],
        # ...
      ]
    end
    ```

3. Configure Commanded to use the `EventStore` adapter:

    ```elixir
    config :commanded,
      event_store_adapter: Commanded.EventStore.Adapters.EventStore
    ```

4. Configure the `eventstore` in each environment's mix config file (e.g. `config/dev.exs`), specifying usage of the Commanded JSON serializer:

    ```elixir
    config :eventstore, EventStore.Storage,
      serializer: Commanded.Serialization.JsonSerializer,
      username: "postgres",
      password: "postgres",
      database: "eventstore_dev",
      hostname: "localhost",
      pool_size: 10
    ```

5. Create the `eventstore` database and tables using the `mix` task:

    ```console
    $ mix event_store.create
    ```

---

## Greg Young's Event Store

[Event Store](https://geteventstore.com/) is an open-source, functional database with Complex Event Processing in JavaScript. It can run as a cluster of nodes containing the same data, which remains available for writes provided at least half the nodes are alive and connected.

The quickest way to get started with the Event Store is by using their official [Event Store Docker container](https://store.docker.com/community/images/eventstore/eventstore).

The Commanded adapter uses the [Extreme](https://github.com/exponentially/extreme) Elixir TCP client to connect to the Event Store.

1. Add `commanded_extreme_adapter` to your list of dependencies in `mix.exs`:

    ```elixir
    def deps do
      [{:commanded_extreme_adapter, "~> 0.1"}]
    end
    ```

2. Configure Commanded to use the event store adapter:

    ```elixir
    config :commanded,
      event_store_adapter: Commanded.EventStore.Adapters.Extreme
    ```

3. Configure the `extreme` library connection with your Event Store connection details:

    ```elixir
    config :extreme, :event_store,
      db_type: :node,
      host: "localhost",
      port: 1113,
      username: "admin",
      password: "changeit",
      reconnect_delay: 2_000,
      max_attempts: :infinity
    ```

4. Configure the `commanded_extreme_adapter` to use the Commanded JSON serializer and specify a stream prefix to be used by all Commanded event streams:

    ```elixir
    config :commanded_extreme_adapter,
      serializer: Commanded.Serialization.JsonSerializer,
      stream_prefix: "commandeddev"
    ```

    The stream prefix is used for category projections and event handler subscriptions. It **must not** contain a dash character ("-").

### Running the Event Store

You **must** run the Event Store with all projections enabled and standard projections started.

Use the `--run-projections=all --start-standard-projections=true` flags when running the Event Store executable.

---

## Writing your own event store provider

To use an alternative event store with Commanded you will need to implement the `Commanded.EventStore` behaviour. This defines the contract to be implemented by an adapter module to allow an event store to be used with Commanded. Tests to verify an adapter conforms to the behaviour are provided in `test/event_store_adapter`.

You can use one of the existing adapters ([commanded_eventstore_adapter](https://github.com/slashdotdash/commanded-eventstore-adapter) or [commanded_extreme_adapter](https://github.com/slashdotdash/commanded-extreme-adapter)) to understand what is required.
