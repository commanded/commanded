BEGIN;
  -- record schema migration
  INSERT INTO schema_migrations (major_version, minor_version, patch_version) VALUES (0, 11, 0);

  ALTER TABLE streams ADD COLUMN stream_version bigint DEFAULT 0;

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
