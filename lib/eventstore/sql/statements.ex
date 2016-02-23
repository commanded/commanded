defmodule EventStore.Sql.Statements do
  def initializers do
    [
      create_streams,
      create_stream_uuid_index,
      create_events,
      create_event_stream_id_index,
      create_event_stream_id_and_version_index
    ]  
  end

  def create_streams do
"""
CREATE TABLE IF NOT EXISTS streams
(
    stream_id BIGSERIAL PRIMARY KEY NOT NULL,
    stream_uuid char(36) NOT NULL,
    created_at timestamp NOT NULL,
    type text NOT NULL
);
"""
  end

  def create_stream_uuid_index do
"""
CREATE UNIQUE INDEX IF NOT EXISTS ix_streams_stream_uuid ON streams (stream_uuid);
"""
  end

  def create_events do
"""
CREATE TABLE IF NOT EXISTS events
(
    event_id BIGSERIAL PRIMARY KEY NOT NULL,
    stream_id bigint NOT NULL,
    stream_version bigint NOT NULL,
    created_at timestamp NOT NULL,
    correlation_id char(36),
    type text NOT NULL,
    headers bytea NULL,
    payload bytea NOT NULL
);
"""
  end

  def create_event_stream_id_index do
"""
CREATE INDEX IF NOT EXISTS ix_events_stream_id ON events (stream_id);
"""
  end

  def create_event_stream_id_and_version_index do
"""
CREATE UNIQUE INDEX IF NOT EXISTS ix_events_stream_id_stream_version ON events (stream_id, stream_version DESC);
"""
  end

  def create_stream do
"""
INSERT INTO streams (stream_uuid, created_at, type)
VALUES ($1, NOW(), $2)
RETURNING stream_id;
"""    
  end

  def create_event do
"""
INSERT INTO events (stream_id, stream_version, created_at, correlation_id, type, headers, payload)
VALUES ($1, $2, NOW(), '', $3, NULL, decode('013d7d16d7ad4fefb61bd95b765c8ceb', 'hex'));
"""    
  end

  def query_stream_id do
"""
SELECT stream_id FROM streams
WHERE stream_uuid = $1;
"""    
  end

  def query_latest_version do
"""
SELECT stream_version FROM events
WHERE stream_id = $1
ORDER BY stream_version DESC
LIMIT 1;
"""    
  end
end