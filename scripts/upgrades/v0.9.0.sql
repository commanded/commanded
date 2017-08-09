BEGIN;

  ALTER TABLE events ADD causation_id text;

COMMIT;
