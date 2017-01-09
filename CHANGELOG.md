# Changelog

## v0.7.3

### Enhancements

- Upgrade `fsm` dependency to v0.3.0 to remove Elixir 1.4 compiler warnings.

## v0.7.2

### Enhancements

- Stream all events forward ([#34](https://github.com/slashdotdash/eventstore/issues/34)).

## v0.7.1

### Enhancements

- Allow snapshots to be deleted ([#26](https://github.com/slashdotdash/eventstore/issues/26)).

## v0.7.0

### Enhancements

- Subscribe to a single stream, or all streams, from a specified start position ([#17](https://github.com/slashdotdash/eventstore/issues/17)).

## v0.6.2

### Bug fixes

- Subscriptions that are at max capacity should wait until all pending events have been acknowledged by the subscriber being catching up with any unseen events.

## v0.6.1

### Enhancements

- Use IO lists to build insert events SQL statement ([#23](https://github.com/slashdotdash/eventstore/issues/23)).

## v0.6.0

### Enhancements

- Use `NaiveDateTime` for each recorded event's `created_at` property.

## v0.5.2

### Enhancements

- Provide typespecs for the public API ([#16](https://github.com/slashdotdash/eventstore/issues/16))
- Fix compilation warnings in mix database task ([#14](https://github.com/slashdotdash/eventstore/issues/14))

### Bug fixes

- Read stream forward does not use count to limit returned events ([#10](https://github.com/slashdotdash/eventstore/issues/10))

## v0.5.0

### Enhancements

- Ack handled events in subscribers ([#18](https://github.com/slashdotdash/eventstore/issues/18)).
- Buffer events between publisher and subscriber ([#19](https://github.com/slashdotdash/eventstore/issues/19)).
