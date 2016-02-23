defmodule EventStore.Storage.Event do
  require Logger

  alias EventStore.Sql.Statements
  alias EventStore.Storage.Event

  def append(conn, stream_id, expected_version, events) do
    case Event.Query.latest_version(conn, stream_id) do
      {:ok, ^expected_version} -> Event.Appender.execute(conn, stream_id, expected_version, events)
      {:ok, _} -> {:error, :wrong_expected_version}
      {:error, reason} -> {:error, reason}
    end
  end

  defmodule Appender do
    def execute(conn, stream_id, expected_version, events) do
      conn
      |> Postgrex.transaction(&execute_within_transaction(&1, stream_id, expected_version, events))
      |> handle_response(stream_id)
    end

    defp execute_within_transaction(transaction, stream_id, expected_version, events) do
      {:ok, query} = prepare_query(transaction)

      initial_stream_version = expected_version + 1

      rollback =
        events
        |> Enum.with_index(initial_stream_version)
        |> Enum.any?(fn {_event,stream_version} ->
           case append_event(transaction, query, stream_id, stream_version) do
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

    defp prepare_query(transaction) do
      Postgrex.prepare(transaction, "create_event", Statements.create_event)
    end

    defp append_event(transaction, query, stream_id, stream_version) do
      Postgrex.execute(transaction, query, [stream_id, stream_version, "type"])
    end

    defp handle_response({:ok, result}, stream_id) do
      Logger.info "appended #{result} events to stream id #{stream_id}"
      {:ok, result}
    end

    defp handle_response({:error, reason}, stream_id) do
      Logger.warn "failed to append events to stream id #{stream_id} due to #{reason}"
      {:error, reason}
    end
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
