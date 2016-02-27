# TODO

-[x] Insert events performance, investigate inserting all events in single query using multirow value insert (example below).
	
	INSERT INTO films (code, title, did, date_prod, kind) VALUES
    ('B6717', 'Tampopo', 110, '1985-02-10', 'Comedy'),
    ('HG120', 'The Dinner Game', 140, DEFAULT, 'Comedy');

    From http://www.postgresql.org/docs/9.4/static/sql-insert.html

    Resulted in a 58.96% reduction in event append. For 100 events: from 24,479.62 µs/op to 9,738.10 µs/op.

-[ ] Limit of ~30,000 parameters per query, so batch event inserts if more than 5,000 events (30k / 6 params per event insert)

-[ ] Connection pool for Postgrex (using [poolboy](https://github.com/devinus/poolboy) library)

## Event payload

-[ ] Remove constraint on `event_type` column from `events` table
-[ ] Allow `EventData` payload to be any type, not just an Elixir struct 
-[ ] Handle null `event_type` when reading events, just deserialize from JSON (using Poison).