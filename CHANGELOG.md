# Changelog

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
