defmodule EventStore.Storage.QueryLatestEventId do
  alias EventStore.Sql.Statements

  def execute(conn) do
    conn
    |> Postgrex.query(Statements.query_latest_event_id, [], pool: DBConnection.Poolboy)
    |> handle_response
  end

  defp handle_response({:ok, %Postgrex.Result{num_rows: 0}}) do
    {:ok, 0}
  end

  defp handle_response({:ok, %Postgrex.Result{rows: [[event_id]]}}) do
    {:ok, event_id}
  end
end
