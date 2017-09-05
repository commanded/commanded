defmodule EventStore.Storage.QueryStreamInfo do
  @moduledoc false
  alias EventStore.Sql.Statements

  def execute(conn, stream_uuid) do
    conn
    |> Postgrex.query(Statements.query_stream_id_and_latest_version, [stream_uuid], pool: DBConnection.Poolboy)
    |> handle_response
  end

  defp handle_response({:ok, %Postgrex.Result{num_rows: 0}}) do
    {:ok, nil, 0}
  end

  defp handle_response({:ok, %Postgrex.Result{rows: [[stream_id, nil]]}}) do
    {:ok, stream_id, 0}
  end

  defp handle_response({:ok, %Postgrex.Result{rows: [[stream_id, stream_version]]}}) do
    {:ok, stream_id, stream_version}
  end
end
