defmodule EventStore.Storage.Stream do
  require Logger

  alias EventStore.Sql.Statements

  def create(conn, stream_uuid) do
    Logger.info "attempting to create stream #{stream_uuid}"

    conn
    |> Postgrex.query(Statements.create_stream, [stream_uuid, "default"])
    |> handle_response(stream_uuid)
  end

  defp handle_response({:ok, reply}, stream_uuid) do
    stream_id = reply.rows |> List.first |> List.first
    Logger.info "created stream #{stream_uuid} with id #{stream_id}"
    {:ok, stream_id}
  end

  defp handle_response({:error, %Postgrex.Error{postgres: %{constraint: "ix_streams_stream_uuid"}}}, stream_uuid) do
    Logger.info "failed to create stream #{stream_uuid}, already exists"
    {:error, :wrong_expected_version}
  end

  defp handle_response({:error, error}, stream_uuid) do
    Logger.info "failed to create stream #{stream_uuid}"
    {:error, error}
  end
end
