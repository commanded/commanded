# Upgrading an EventStore

The [CHANGELOG](https://github.com/slashdotdash/eventstore/blob/master/CHANGELOG.md) is used to indicate when a schema migration is required for a given version of the EventStore.

The [migration scripts](https://github.com/slashdotdash/eventstore/tree/master/scripts/upgrades) are provided for upgrading an existing EventStore. Creating an EventStore, using the `mix event_store.create` task, will always use the latest database schema.

You must stop the `:eventstore` application to apply an upgrade. It is *always* worth taking a full backup of the EventStore database before applying an upgrade.

Since v0.10.0 a `schema_migrations` table has been used to record when each migration took place.
