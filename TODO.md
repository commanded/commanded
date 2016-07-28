# TODO

-[ ] Assign event `created_at` timestamp by writer process, not database.

-[ ] Restart writer process, assigns next event id on append.

-[ ] Subscription should ack received events to resume from last seen.

-[ ] Unsubscribe from stream should remove subscription process and entry from storage.

-[ ] Read stream forward should use count to limit number of events (and enforce a default limit of 1,000 events).

-[ ] Stream type property when creating an event stream.

-[ ] Limit of ~30,000 parameters per query, so inserts of more than ~5,000 events (30k / 6 params per event insert) will fail.
     Use transaction and batch inserts into ~5k chunks.

 -[ ] Shutdown `EventStore.Streams.Stream` processes after a period of inactivity
