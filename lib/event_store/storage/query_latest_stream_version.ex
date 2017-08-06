defmodule EventStore.Storage.QueryLatestStreamVersion do
  alias EventStore.Sql.Statements

  def execute(conn, stream_id) do
    conn
    |> Postgrex.query(Statements.query_latest_version, [stream_id], pool: DBConnection.Poolboy)
    |> handle_response
  end

  defp handle_response({:ok, %Postgrex.Result{num_rows: 0}}) do
    # no stored events, so latest version is 0
    {:ok, 0}
  end

  defp handle_response({:ok, %Postgrex.Result{rows: [[latest_version]]}}) do
    {:ok, latest_version}
  end
end
