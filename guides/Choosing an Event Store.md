# Choosing an event store

You must decide which event store to use with Commanded. You have a choice between two existing event stores:

- PostgreSQL-based Elixir [EventStore](https://github.com/commanded/eventstore) ([adapter](https://github.com/commanded/commanded-eventstore-adapter)).

- [EventStoreDB](https://www.eventstore.com/) ([adapter](https://github.com/commanded/commanded-extreme-adapter)).

There is also an [in-memory event store adapter](https://github.com/commanded/commanded/wiki/In-memory-event-store) for *test use only*.

Want to use a different event store? Then you will need to write your own event store provider as described below.

---

## PostgreSQL-based Elixir EventStore

Use [`:commanded_eventstore_adapter`](https://github.com/commanded/commanded-eventstore-adapter) to persist events to a PostgreSQL database. As the name implies, this is the adapter for [EventStore](https://github.com/commanded/eventstore), which is open-source event store using PostgreSQL for persistence and implemented in Elixir.

---

## [EventStoreDB](https://www.eventstore.com/)

Use [`:commanded_extreme_adapter`](https://github.com/commanded/commanded-extreme-adapter) to persist events to [EventStoreDB](https://www.eventstore.com/): an open-source database, the best data storage solution for event-sourced systems. It can be run as a cluster of nodes containing the same data, which remains available for writes provided at least half the nodes are alive and connected.

The quickest way to get started with EventStoreDB is by using their official [EventStoreDB Docker container](https://hub.docker.com/r/eventstore/eventstore).

The Commanded adapter uses the [`:extreme`](https://github.com/exponentially/extreme) Elixir TCP client to connect to EventStoreDB.

### Running EventStoreDB

You **must** run EventStoreDB with all projections enabled and standard projections started.

Use the `--run-projections=all --start-standard-projections=true` flags when running the EventStoreDB executable.

---

## Writing your own event store provider

To use an alternative event store with Commanded you will need to implement the `Commanded.EventStore.Adapter` behaviour. This defines the contract to be implemented by an adapter module to allow an event store to be used with Commanded. Tests to verify an adapter conforms to the behaviour are provided in `test/event_store_adapter`.

You can use one of the existing adapters ([commanded_eventstore_adapter](https://github.com/commanded/commanded-eventstore-adapter) or [commanded_extreme_adapter](https://github.com/commanded/commanded-extreme-adapter)) to understand what is required.
