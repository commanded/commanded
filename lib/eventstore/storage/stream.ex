defmodule EventStore.Storage.Stream do
  require Logger

  alias EventStore.EventData
  alias EventStore.Sql.Statements
  alias EventStore.Storage.Stream
  alias EventStore.Storage.Appender

  def append_to_stream(conn, stream_uuid, expected_version, events) when expected_version == 0 do
    conn
    |> create_stream(stream_uuid)
    |> append_events(conn, expected_version, events)
  end

  def append_to_stream(conn, stream_uuid, expected_version, events) when expected_version > 0 do
    conn
    |> lookup_stream_id(stream_uuid)
    |> append_events(conn, expected_version, events)
  end

  defp append_events({:ok, stream_id}, conn, expected_version, events) when is_number(stream_id) do
    Appender.append(conn, stream_id, expected_version, events)
  end

  defp append_events({:error, reason}, conn, expected_version, events) do
    {:error, reason}
  end

  defp create_stream(conn, stream_uuid) do
    Logger.debug "attempting to create stream #{stream_uuid}"

    conn
    |> Postgrex.query(Statements.create_stream, [stream_uuid, "default"])
    |> handle_create_response(stream_uuid)
  end

  defp handle_create_response({:ok, reply}, stream_uuid) do
    stream_id = reply.rows |> List.first |> List.first
    Logger.debug "created stream #{stream_uuid} with id #{stream_id}"
    {:ok, stream_id}
  end

  defp handle_create_response({:error, %Postgrex.Error{postgres: %{constraint: "ix_streams_stream_uuid"}}}, stream_uuid) do
    Logger.warn "failed to create stream #{stream_uuid}, already exists"
    {:error, :wrong_expected_version}
  end

  defp handle_create_response({:error, error}, stream_uuid) do
    Logger.warn"failed to create stream #{stream_uuid}"
    {:error, error}
  end  

  defp lookup_stream_id(conn, stream_uuid) do
    conn
    |> Postgrex.query(Statements.query_stream_id, [stream_uuid])
    |> handle_lookup_response(stream_uuid)
  end

  defp handle_lookup_response({:ok, %Postgrex.Result{num_rows: 0}}, stream_uuid) do
    Logger.warn "attempted to append events to missing stream #{stream_uuid}"
    {:error, :stream_not_found}
  end

  defp handle_lookup_response({:ok, %Postgrex.Result{rows: rows}}, _stream_uuid) do
    stream_id = rows |> List.first |> List.first
    {:ok, stream_id}
  end
end
