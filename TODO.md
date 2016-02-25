# TODO

-[ ] Remove constraint on `event_type` column from `events` table
-[ ] Allow `EventData` payload to be any type, not just an Elixir struct 
-[ ] Handle null `event_type` when reading events, just deserialize from JSON (using Poison).