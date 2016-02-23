defmodule EventStore.Sql.Statements do
  def initializers do
    [
      create_streams,
      create_stream_uuid_index,
      create_events,
      create_event_stream_id_index
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

  def create_stream do
"""
INSERT INTO streams (stream_uuid, created_at, type)
VALUES ($1, NOW(), $2)
RETURNING stream_id;
"""    
  end
end