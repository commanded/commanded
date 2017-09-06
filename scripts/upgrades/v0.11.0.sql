BEGIN;

  CREATE TABLE IF NOT EXISTS schema_migrations
  (
      major_version int NOT NULL,
      minor_version int NOT NULL,
      patch_version int NOT NULL,
      migrated_at timestamp without time zone default (now() at time zone 'UTC') NOT NULL,
      PRIMARY KEY(major_version, minor_version, patch_version)
  );

  -- record schema migration
  INSERT INTO schema_migrations (major_version, minor_version, patch_version) VALUES (0, 11, 0);

  -- add `stream_version` column to `streams` table
  ALTER TABLE streams ADD COLUMN stream_version bigint DEFAULT 0;

  -- seed `stream_version` from `events` table for existing streams
  UPDATE streams s
  SET stream_version = (
    SELECT COALESCE(e.stream_version, 0)
    FROM events e
    WHERE e.stream_id = s.stream_id
    ORDER BY e.stream_version DESC
    LIMIT 1
  );

  -- enforce `stream_version` is not NULL
  ALTER TABLE streams ALTER COLUMN stream_version SET NOT NULL;

COMMIT;
