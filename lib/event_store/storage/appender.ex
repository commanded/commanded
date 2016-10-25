defmodule EventStore.Storage.Appender do
  @moduledoc """
  Append-only storage of events to a stream
  """

  require Logger

  alias EventStore.Sql.Statements

  @doc """
  Append the given list of events to the given stream.
  Returns `{:ok, count}` on success, where count indicates the number of appended events.
  """
  def append(conn, stream_id, events) do
    execute_using_multirow_value_insert(conn, stream_id, events)
  end

  defp execute_using_multirow_value_insert(conn, stream_id, events) do
    statement = build_insert_statement(events)
    parameters = build_insert_parameters(events)

    conn
    |> Postgrex.query(statement, parameters)
    |> handle_response(stream_id)
  end

  defp build_insert_statement(events) do
    Statements.create_events(length(events))
  end

  defp build_insert_parameters(events) do
    events
    |> Enum.map(fn(event) ->
      [
        event.event_id,
        event.stream_id,
        event.stream_version,
        event.correlation_id,
        event.event_type,
        event.data,
        event.metadata,
        event.created_at,
      ]
    end)
    |> List.flatten
  end

  defp handle_response({:ok, %Postgrex.Result{num_rows: 0}}, stream_id) do
    _ = Logger.info(fn -> "failed to append any events to stream id #{stream_id}" end)
    {:ok, 0}
  end

  defp handle_response({:ok, %Postgrex.Result{num_rows: num_rows}}, stream_id) do
    _ = Logger.info(fn -> "appended #{num_rows} events to stream id #{stream_id}" end)
    {:ok, num_rows}
  end

  defp handle_response({:error, %Postgrex.Error{postgres: %{code: :foreign_key_violation, message: message}}}, stream_id) do
    _ = Logger.warn(fn -> "failed to append events to stream id #{stream_id} due to: #{inspect message}" end)
    {:error, :stream_not_found}
  end

  defp handle_response({:error, %Postgrex.Error{postgres: %{code: :unique_violation, message: message}}}, stream_id) do
    _ = Logger.warn(fn -> "failed to append events to stream id #{stream_id} due to: #{inspect message}" end)
    {:error, :wrong_expected_version}
  end

  defp handle_response({:error, reason}, stream_id) do
    _ = Logger.warn(fn -> "failed to append events to stream id #{stream_id} due to: #{inspect reason}" end)
    {:error, reason}
  end
end
