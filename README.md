# EventStore

CQRS event store implemented in Elixir. Uses [PostgreSQL](http://www.postgresql.org/) (v9.5 or later) as the underlying storage engine.

EventStore supports [running on a cluster of nodes](guides/Cluster.md) (since v0.11). Stream processes will be distributed amongst all available nodes, events are published to subscribers running on any node.

[Changelog](CHANGELOG.md)

MIT License

[![Build Status](https://travis-ci.org/slashdotdash/eventstore.svg?branch=master)](https://travis-ci.org/slashdotdash/eventstore)

---

### Overview

- [Getting started](guides/Getting%20Started.md)
- [Using the EventStore](guides/Usage.md)
  - [Writing to a stream](guides/Usage.md#writing-to-a-stream)
  - [Reading from a stream](guides/Usage.md#reading-from-a-stream)
  - [Reading from all streams](guides/Usage.md#reading-from-all-streams)
  - [Stream from all streams](guides/Usage.md#stream-from-all-streams)
  - [Subscribe to streams](guides/Subscriptions.md)
    - [Ack received events](guides/Subscriptions.md#ack-received-events)
    - [Example subscriber](guides/Subscriptions.md#example-subscriber)
- [Running on a cluster](guides/Cluster.md)
- [Event serialization](guides/Event%20Serialization.md)
  - [Example JSON serializer](guides/Event%20Serialization.md#example-json-serializer)
- [Upgrading an EventStore](guides/Upgrades.md)
- [Used in production?](#used-in-production)
- [Backup and administration](#backup-and-administration)
- [Benchmarking performance](#benchmarking-performance)
- [Contributing](#contributing)
  - [Contributors](#contributors)
- [Need help?](#need-help)

---

## Example usage

Append events to a stream:

```elixir
stream_uuid = UUID.uuid4()
expected_version = 0
events = [
  %EventStore.EventData{
    event_type: "Elixir.ExampleEvent",
    data: %ExampleEvent{key: "value"},
    metadata: %{user: "someuser@example.com"},
  }
]

:ok = EventStore.append_to_stream(stream_uuid, expected_version, events)
```

Read all events from a single stream, starting at the stream's first event:

```elixir
{:ok, events} = EventStore.read_stream_forward(stream_uuid)
```

More: [Using the EventStore](guides/Usage.md)

Subscribe to events appended to all streams:

```elixir
{:ok, subscription} = EventStore.subscribe_to_all_streams("example_subscription", self())

receive do
  {:events, events} ->
    # ... process events & ack receipt    
    EventStore.ack(subscription, events)
end
```

More: [Subscribe to streams](guides/Subscriptions.md)

## Used in production?

Yes, this event store is being used in production.

PostgreSQL is used for the underlying storage. Providing guarantees to store data securely. It is ACID-compliant and transactional. PostgreSQL has a proven architecture. A strong reputation for reliability, data integrity, and correctness.

## Backup and administration

You can use any standard PostgreSQL tool to manage the event store data:

- [Backup and restore](https://www.postgresql.org/docs/current/static/backup-dump.html).
- [Continuous archiving and Point-in-Time Recovery (PITR)](https://www.postgresql.org/docs/current/static/continuous-archiving.html).

## Benchmarking performance

Run the benchmark suite using mix with the `bench` environment, as configured in `config/bench.exs`. Logging is disabled for benchmarking.

```console
$ MIX_ENV=bench mix do es.reset, app.start, bench
```

Example output:

```
## AppendEventsBench
append events, single writer                  100   10170.26 µs/op
append events, 10 concurrent writers           20   85438.80 µs/op
append events, 100 concurrent writers           2   1102006.00 µs/op
## ReadEventsBench
read events, single reader                   1000   1578.10 µs/op
read events, 10 concurrent readers            100   16799.80 µs/op
read events, 100 concurrent readers            10   167397.30 µs/op
```

## Contributing

Pull requests to contribute new or improved features, and extend documentation are most welcome.

Please follow the existing coding conventions, or refer to the [Elixir style guide](https://github.com/niftyn8/elixir_style_guide).

You should include unit tests to cover any changes.

### Contributors

- [Andrey Akulov](https://github.com/astery)
- [Craig Savolainen](https://github.com/maedhr)
- [David Soff](https://github.com/Davidsoff)
- [Jan Vereecken](https://github.com/javereec)
- [Olafur Arason](https://github.com/olafura)
- [Paul Iannazzo](https://github.com/boxxxie)
- [Simon Harris](https://github.com/harukizaemon)
- [Stuart Corbishley](https://github.com/stuartc)

## Need help?

Please [open an issue](https://github.com/slashdotdash/eventstore/issues) if you encounter a problem, or need assistance.

For commercial support, and consultancy, please contact [Ben Smith](mailto:ben@10consulting.com).
