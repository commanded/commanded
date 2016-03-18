# TODO

-[x] Insert events performance, investigate inserting all events in single query using multirow value insert (example below).

	INSERT INTO films (code, title, did, date_prod, kind) VALUES
    ('B6717', 'Tampopo', 110, '1985-02-10', 'Comedy'),
    ('HG120', 'The Dinner Game', 140, DEFAULT, 'Comedy');

    From http://www.postgresql.org/docs/9.4/static/sql-insert.html

    Resulted in a 58.96% reduction in event append. For 100 events: from 24,479.62 µs/op to 9,738.10 µs/op.

-[x] Use `INSERT RETURNING` when appending events to stream so that event id and timestamp can be returned.
     http://www.postgresql.org/docs/9.5/static/sql-insert.html

-[x] Connection pool for Postgrex (using [poolboy](https://github.com/devinus/poolboy) library)

-[x] Don't (de)serialize event payload & headers. Persist binary data, allow EventStore consumers to handle serialization.

-[ ] Subscription should ack received events to resume from last seen.

-[ ] Unsubscribe from stream should remove subscription process and entry from storage.

-[ ] Read stream forward should use count to limit number of events (and enforce a default limit of 1,000 events).

-[ ] Stream type property when creating an event stream.

-[ ] Limit of ~30,000 parameters per query, so inserts of more than ~5,000 events (30k / 6 params per event insert) will fail.
     Use transaction and batch inserts into ~5k chunks.

 -[ ] Supervisor for `EventStore.Publisher` and `EventStore.Subscriptions` using `:one_for_all` strategy so that event publishing
      can safely crash and be restarted if there is a problem with either.

 -[ ] Shutdown `EventStore.Streams.Stream` processes after a period of inactivity
