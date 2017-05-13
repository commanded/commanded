# Changelog

## v0.10.0

### Enhancements

- Extract event store integration to a behaviour (`Commanded.EventStore`). This defines the contract to be implemented by an event store adapter. It allows additional event store databases to be used with Commanded.

  By default, a `GenServer` in-memory event store adapter is used. This should **only be used for testing** as there is no persistence.

  The existing PostgreSQL-based [eventstore](https://github.com/slashdotdash/eventstore) integration has been extracted as a separate package ([commanded_eventstore_adapter](https://github.com/slashdotdash/commanded-eventstore-adapter)). There is also a new adapter for Greg Young's Event Store using the Extreme library ([commanded_extreme_adapter](https://github.com/slashdotdash/commanded-extreme-adapter)).

  You must install the required event store adapter package and update your environment configuration to specify the `:event_store_adapter` module. See the [README](https://github.com/slashdotdash/commanded/blob/master/README.md) for details.

## v0.9.0

### Enhancements

- Stream events from event store when rebuilding aggregate state.

## v0.8.5

### Enhancements

- Upgrade to Elixir 1.4 and remove compiler warnings.

## v0.8.4

### Enhancements

- Event handler and process manager subscriptions should be created from a given stream position ([#14](https://github.com/slashdotdash/commanded/issues/14)).
- Stop process manager instance after reaching its final state ([#24](https://github.com/slashdotdash/commanded/issues/24)).

## v0.8.3

### Enhancements

- Middleware `after_failure` callback is executed even when a middleware halts execution.

## v0.8.2

### Bug fixes

- JsonSerializer should ensure event type atom exists when deserializing ([#28](https://github.com/slashdotdash/commanded/issues/28)).

## v0.8.1

### Enhancements

- Command handlers should be optional by default ([#30](https://github.com/slashdotdash/commanded/issues/30)).

## v0.8.0

### Enhancements

- Simplify aggregate roots and process managers ([#31](https://github.com/slashdotdash/commanded/issues/31)).

## v0.7.1

### Bug fixes

- Restarting aggregate process should load all events from its stream in batches. The Event Store read stream default limit is 1,000 events.

## v0.7.0

### Enhancements

- Command handling middleware allows a command router to define middleware modules that are executed before, and after success or failure of each command dispatch ([#12](https://github.com/slashdotdash/commanded/issues/12)).

## v0.6.3

### Enhancements

- Process manager instance processes event non-blocking to prevent timeout during event processing and any command dispatching. It persists last seen event id to ensure events are handled only once.

## v0.6.2

### Enhancements

- Command dispatch timeout. Allow a `timeout` value to be configured during command registration or dispatch. This overrides the default timeout of 5 seconds. The same as the default `GenServer` call timeout.

### Bug fixes

- Fix pending aggregates restarts: supervisor restarts aggregate process but it cannot accept commands ([#22](https://github.com/slashdotdash/commanded/pull/22)).

## v0.6.1

### Enhancements

- Upgrade `eventstore` mix dependency to v0.6.0 to use support for recorded events created_at as `NaiveDateTime`.

## v0.6.0

### Enhancements

- Confirm receipt of events in event handler and process manager router ([#19](https://github.com/slashdotdash/commanded/pull/19)).
- Convert keys to atoms when decoding JSON using Poison decoder.
- Prefix process manager instance snapshot uuid with process manager name.
- Multi command dispatch registration in router ([#16](https://github.com/slashdotdash/commanded/issues/16)).

## v0.5.0

### Enhancements

- Include event metadata as second argument to event handlers. An event handler must now implement the `Commanded.Event.Handler` behaviour consisting of a single `handle_event/2` function.

## v0.4.0

### Enhancements

- Macro to assist with building process managers ([README](https://github.com/slashdotdash/commanded/tree/feature/process-manager-macro#process-managers)).

## v0.3.1

### Enhancements

- Include unit test event assertion function: `assert_receive_event/2` ([#13](https://github.com/slashdotdash/commanded/pull/13)).
- Include top level application in mix config.

## v0.3.0

### Enhancements

- Don't persist an aggregate's pending events when executing a command returns an error ([#10](https://github.com/slashdotdash/commanded/pull/10)).

### Bug fixes

- Ensure an aggregate's pending events are persisted in the order they were applied.

## v0.2.1

### Enhancements

- Support integer, atom or strings as an aggregate root UUID ([#7](https://github.com/slashdotdash/commanded/pull/7)).
