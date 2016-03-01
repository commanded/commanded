defmodule EventStore.Storage.Appender do
  @moduledoc """
  Append-only storage of events for a stream
  """
  
  require Logger

  alias EventStore.EventData
  alias EventStore.Sql.Statements
  alias EventStore.Storage.Appender

  def append(conn, stream_id, expected_version, events) do
    case Appender.Query.query_latest_version(conn, stream_id) do
      {:ok, ^expected_version} -> execute_using_multirow_value_insert(conn, stream_id, expected_version, events)
      {:ok, latest_version} -> wrong_expected_version(stream_id, expected_version, latest_version)
      {:error, reason} -> failed_to_append(stream_id, reason)
    end
  end

  defp wrong_expected_version(stream_id, expected_version, latest_version) do
    Logger.warn "failed to append events to stream id #{stream_id}, expected version #{expected_version} but latest version is #{latest_version}"
    {:error, :wrong_expected_version}
  end

  defp failed_to_append(stream_id, reason) do
    Logger.warn "failed to append events to stream id #{stream_id} due to #{reason}"
    {:error, reason}
  end

  defp execute_using_multirow_value_insert(conn, stream_id, expected_version, events) do
    statement = build_insert_statement(events)
    parameters = build_insert_parameters(stream_id, expected_version, events)

    conn
    |> Postgrex.query(statement, parameters)
    |> handle_response(stream_id)
  end

  defp build_insert_statement(events) do
    Statements.create_event(length(events))
  end

  defp build_insert_parameters(stream_id, expected_version, events) do
    events
    |> prepare_events(stream_id, expected_version)
    |> Enum.reduce([], fn(event, parameters) ->
      parameters ++ [
        event.stream_id,
        event.stream_version,
        event.correlation_id,
        event.event_type,
        event.headers,
        event.payload
      ]
    end)
  end

  defp prepare_events(events, stream_id, expected_version) do
    initial_stream_version = expected_version + 1

    events
    |> Enum.map(&assign_stream_id(&1, stream_id))
    |> Enum.with_index(initial_stream_version)
    |> Enum.map(&assign_stream_version/1)
    |> Enum.map(&assign_event_type/1)
    |> Enum.map(&encode_headers/1)
    |> Enum.map(&encode_payload/1)
  end

  defp assign_stream_id(%EventData{} = event, stream_id) do
    %EventData{event | stream_id: stream_id}
  end

  defp assign_stream_version({%EventData{} = event, stream_version}) do
    %EventData{event | stream_version: stream_version}
  end

  defp assign_event_type(%EventData{payload: payload} = event) do
    event_type = payload.__struct__ |> Atom.to_string
    %EventData{event | event_type: event_type}
  end

  defp encode_headers(%EventData{headers: headers} = event) do
    %EventData{event | headers: Poison.encode!(headers)}
  end

  defp encode_payload(%EventData{payload: payload} = event) do
    %EventData{event | payload: Poison.encode!(payload)}
  end

  defp handle_response({:ok, %Postgrex.Result{num_rows: num_rows}}, stream_id) do
    Logger.info "appended #{num_rows} events to stream id #{stream_id}"
    {:ok, num_rows}
  end

  defp handle_response({:error, reason}, stream_id) do
    Logger.warn "failed to append events to stream id #{stream_id} due to #{reason}"
    {:error, reason}
  end

  defmodule Query do
    def query_latest_version(conn, stream_id) do
      conn
      |> Postgrex.query(Statements.query_latest_version, [stream_id])
      |> handle_response
    end

    defp handle_response({:ok, %Postgrex.Result{num_rows: 0}}) do
      # no stored events, so latest version is 0
      {:ok, 0}
    end

    defp handle_response({:ok, %Postgrex.Result{rows: rows}}) do
      latest_version = rows |> List.first |> List.first
      {:ok, latest_version}
    end
  end
end
