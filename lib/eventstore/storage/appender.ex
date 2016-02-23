defmodule EventStore.Storage.Appender do
  require Logger

  alias EventStore.EventData
  alias EventStore.Sql.Statements
  alias EventStore.Storage.Appender

  def append(conn, stream_id, expected_version, [%EventData{}] = events) do
    case Appender.Query.latest_version(conn, stream_id) do
      {:ok, ^expected_version} -> execute(conn, stream_id, expected_version, events)
      {:ok, _} -> {:error, :wrong_expected_version}
      {:error, reason} -> {:error, reason}
    end
  end

  defp execute(conn, stream_id, expected_version, events) do
    conn
    |> Postgrex.transaction(&execute_within_transaction(&1, stream_id, expected_version, events))
    |> handle_response(stream_id)
  end

  defp execute_within_transaction(transaction, stream_id, expected_version, events) do
    {:ok, query} = prepare_query(transaction)

    initial_stream_version = expected_version + 1

    rollback =
      events
      |> Enum.map(&assign_stream_id(&1, stream_id))
      |> Enum.with_index(initial_stream_version)
      |> Enum.map(&assign_stream_version/1)
      |> Enum.map(&encode_headers/1)
      |> Enum.map(&encode_payload/1)
      |> Enum.any?(fn event ->
         case append_event(transaction, query, event) do
           {:ok, _} -> false
           _ -> true
         end
      end)

    if rollback do
      Postgrex.rollback(transaction)
    else
      length(events)
    end
  end

  defp assign_stream_id(%EventData{} = event, stream_id) do
    %EventData{event | stream_id: stream_id}
  end

  def assign_stream_version({%EventData{} = event, stream_version}) do
    %EventData{event | stream_version: stream_version}
  end

  defp encode_headers(%EventData{headers: headers} = event) do
    %EventData{event | headers: Poison.encode!(headers)}
  end

  defp encode_payload(%EventData{payload: payload} = event) do
    %EventData{event | payload: Poison.encode!(payload)}
  end

  defp prepare_query(transaction) do
    Postgrex.prepare(transaction, "create_event", Statements.create_event)
  end

  defp append_event(transaction, query, %EventData{} = event) do
    Postgrex.execute(transaction, query, [
      event.stream_id, 
      event.stream_version, 
      event.correlation_id,
      event.event_type,
      event.headers, 
      event.payload
    ])
  end

  defp handle_response({:ok, result}, stream_id) do
    Logger.info "appended #{result} events to stream id #{stream_id}"
    {:ok, result}
  end

  defp handle_response({:error, reason}, stream_id) do
    Logger.warn "failed to append events to stream id #{stream_id} due to #{reason}"
    {:error, reason}
  end

  defmodule Query do
    def latest_version(conn, stream_id) do
      conn
      |> Postgrex.query(Statements.query_latest_version, [stream_id])
      |> handle_response
    end

    defp handle_response({:ok, %Postgrex.Result{num_rows: 0}}) do
      # no stored events, so latest version is 0
      {:ok, 0}
    end

    defp handle_response({:ok, reply}) do
      IO.inspect reply
      latest_version = reply.rows |> List.first |> List.first
      {:ok, latest_version}
    end
  end
end