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
  INSERT INTO schema_migrations (major_version, minor_version, patch_version) VALUES (0, 9, 0);

  --- add `causation_id` to `events` table
  ALTER TABLE events ADD causation_id text;

COMMIT;
