defmodule EventStore.Storage.Stream do
  @moduledoc """
  Streams are an abstraction around a stream of events for a given stream identity
  """

  require Logger

  alias EventStore.Sql.Statements
  alias EventStore.Storage.{Appender,QueryLatestEventId,QueryLatestStreamVersion,QueryStreamInfo,Reader,Stream}

  def create_stream(conn, stream_uuid) do
    Logger.debug "attempting to create stream #{stream_uuid}"

    conn
    |> Postgrex.query(Statements.create_stream, [stream_uuid, "default"])
    |> handle_create_response(stream_uuid)
  end

  def read_stream_forward(conn, stream_id, start_version, count \\ nil) do
    Reader.read_forward(conn, stream_id, start_version, count)
  end

  def read_all_streams_forward(conn, start_event_id, count \\ nil) do
    Reader.read_all_forward(conn, start_event_id, count)
  end

  def latest_event_id(conn) do
    QueryLatestEventId.execute(conn)
  end

  def stream_info(conn, stream_uuid) do
    QueryStreamInfo.execute(conn, stream_uuid)
  end

  def latest_stream_version(conn, stream_uuid) do
    execute_with_stream_id(conn, stream_uuid, fn stream_id ->
      QueryLatestStreamVersion.execute(conn, stream_id)
    end)
  end

  defp execute_with_stream_id(conn, stream_uuid, execute_fn) do
    case lookup_stream_id(conn, stream_uuid) do
      {:ok, stream_id} -> execute_fn.(stream_id)
      response -> response
    end
  end

  defp handle_create_response({:ok, %Postgrex.Result{rows: [[stream_id]]}}, stream_uuid) do
    Logger.debug "created stream #{stream_uuid} with id #{stream_id}"
    {:ok, stream_id}
  end

  defp handle_create_response({:error, %Postgrex.Error{postgres: %{code: :unique_violation}}}, stream_uuid) do
    Logger.warn "failed to create stream #{stream_uuid}, already exists"
    {:error, :stream_exists}
  end

  defp handle_create_response({:error, error}, stream_uuid) do
    Logger.warn "failed to create stream #{stream_uuid}"
    {:error, error}
  end

  defp lookup_stream_id(conn, stream_uuid) do
    conn
    |> Postgrex.query(Statements.query_stream_id, [stream_uuid])
    |> handle_lookup_response(stream_uuid)
  end

  defp handle_lookup_response({:ok, %Postgrex.Result{num_rows: 0}}, stream_uuid) do
    Logger.warn("attempted to access unknown stream #{stream_uuid}")
    {:error, :stream_not_found}
  end

  defp handle_lookup_response({:ok, %Postgrex.Result{rows: [[stream_id]]}}, _) do
    {:ok, stream_id}
  end
end
