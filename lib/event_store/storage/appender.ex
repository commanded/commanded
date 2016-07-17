defmodule EventStore.Storage.Appender do
  @moduledoc """
  Append-only storage of events to a stream
  """

  require Logger

  alias EventStore.RecordedEvent
  alias EventStore.Sql.Statements

  def append(conn, stream_id, events) do
    execute_using_multirow_value_insert(conn, stream_id, events)
  end

  defp execute_using_multirow_value_insert(conn, stream_id, events) do
    statement = build_insert_statement(events)
    parameters = build_insert_parameters(events)

    conn
    |> Postgrex.query(statement, parameters)
    |> handle_response(stream_id, events)
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
        event.metadata
      ]
    end)
    |> List.flatten
  end

  defp handle_response({:ok, %Postgrex.Result{num_rows: 0}}, stream_id, _events) do
    Logger.info "failed to append any events to stream id #{stream_id}"
    {:ok, 0}
  end

  defp handle_response({:ok, %Postgrex.Result{num_rows: num_rows}}, stream_id, events) do
    Logger.info "appended #{num_rows} events to stream id #{stream_id}"
    {:ok, num_rows}
  end

  defp handle_response({:error, %Postgrex.Error{postgres: %{code: :foreign_key_violation, message: message}}}, stream_id, _events) do
    Logger.warn "failed to append events to stream id #{stream_id} due to: #{message}"
    {:error, :stream_not_found}
  end

  defp handle_response({:error, %Postgrex.Error{postgres: %{code: :unique_violation, message: message}}}, stream_id, _events) do
    Logger.warn "failed to append events to stream id #{stream_id} due to: #{message}"
    {:error, :wrong_expected_version}
  end

  defp handle_response({:error, reason}, stream_id, _events) do
    Logger.warn "failed to append events to stream id #{stream_id} due to: #{reason}"
    {:error, reason}
  end
end
