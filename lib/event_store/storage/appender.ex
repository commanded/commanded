defmodule EventStore.Storage.Appender do
  @moduledoc """
  Append-only storage of events to a stream
  """

  require Logger

  alias EventStore.Sql.Statements

  @doc """
  Append the given list of events to storage

  Returns `{:ok, event_ids}` on success, where `event_ids` is a list of the ids assigned by the database.
  """
  def append(conn, events) do
    execute_using_multirow_value_insert(conn, events)
  end

  defp execute_using_multirow_value_insert(conn, events) do
    statement = build_insert_statement(events)
    parameters = build_insert_parameters(events)

    conn
    |> Postgrex.query(statement, parameters, pool: DBConnection.Poolboy)
    |> handle_response(events)
  end

  defp build_insert_statement(events) do
    Statements.create_events(length(events))
  end

  defp build_insert_parameters(events) do
    events
    |> Enum.flat_map(fn event ->
      [
        event.stream_id,
        event.stream_version,
        event.correlation_id,
        event.causation_id,
        event.event_type,
        event.data,
        event.metadata,
        event.created_at,
      ]
    end)
  end

  defp handle_response({:ok, %Postgrex.Result{num_rows: 0}}, events) do
    _ = Logger.warn(fn -> "failed to append any events to stream id #{stream_id(events)}" end)
    {:ok, []}
  end

  defp handle_response({:ok, %Postgrex.Result{num_rows: num_rows, rows: rows}} = result, events) do
    event_ids = List.flatten(rows)

    _ = Logger.info(fn -> "appended #{num_rows} event(s) to stream id #{stream_id(events)} (event ids: #{Enum.join(event_ids, ", ")})" end)
    {:ok, event_ids}
  end

  defp handle_response({:error, %Postgrex.Error{postgres: %{code: :foreign_key_violation, message: message}}}, events) do
    _ = Logger.warn(fn -> "failed to append events to stream id #{stream_id(events)} due to: #{inspect message}" end)
    {:error, :stream_not_found}
  end

  defp handle_response({:error, %Postgrex.Error{postgres: %{code: :unique_violation, message: message}}}, events) do
    _ = Logger.warn(fn -> "failed to append events to stream id #{stream_id(events)} due to: #{inspect message}" end)
    {:error, :wrong_expected_version}
  end

  defp handle_response({:error, reason}, events) do
    _ = Logger.warn(fn -> "failed to append events to stream id #{stream_id(events)} due to: #{inspect reason}" end)
    {:error, reason}
  end

  defp stream_id([event | _]), do: event.stream_id
end
