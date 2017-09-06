BEGIN;

  -- create `schema_migrations` table
  CREATE TABLE IF NOT EXISTS schema_migrations
  (
      major_version int NOT NULL,
      minor_version int NOT NULL,
      patch_version int NOT NULL,
      migrated_at timestamp without time zone default (now() at time zone 'UTC') NOT NULL,
      PRIMARY KEY(major_version, minor_version, patch_version)
  );

  -- record schema migration
  INSERT INTO schema_migrations (major_version, minor_version, patch_version) VALUES (0, 10, 0);

  -- create new `event_counter` table
  CREATE TABLE event_counter
  (
      event_id bigint PRIMARY KEY NOT NULL
  );

  -- seed event counter with latest `event_id` from `events` table
  INSERT INTO event_counter (event_id)
  SELECT COALESCE(MAX(event_id), 0) FROM events;

  -- disallow further insertions to event counter table
  CREATE RULE no_insert_event_counter AS ON INSERT TO event_counter DO INSTEAD NOTHING;

  -- disallow deletions from event counter table
  CREATE RULE no_delete_event_counter AS ON DELETE TO event_counter DO INSTEAD NOTHING;

  -- prevent updates to events table
  CREATE RULE no_update_events AS ON UPDATE TO events DO INSTEAD NOTHING;

  -- prevent deletion from events table
  CREATE RULE no_delete_events AS ON DELETE TO events DO INSTEAD NOTHING;

COMMIT;
