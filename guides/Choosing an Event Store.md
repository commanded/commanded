# Choosing an event store

For production applications, Commanded only officially supports the PostgreSQL-based Elixir [EventStore](https://github.com/commanded/eventstore) ([adapter](https://github.com/commanded/commanded-eventstore-adapter)).

There is also an [in-memory event store adapter](https://github.com/commanded/commanded/wiki/In-memory-event-store). This provides no persistence and is intended for unit testing and local development only.
