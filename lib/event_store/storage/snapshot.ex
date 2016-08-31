defmodule EventStore.Storage.Snapshot do
  @moduledoc """
  Record serialized snapshot data.
  """

  require Logger

  alias EventStore.Sql.Statements
  alias EventStore.Storage.Snapshot

  defstruct source_uuid: nil, source_version: nil, data: nil, metadata: nil, created_at: nil

  def read_snapshot(conn, source_uuid) do
    Snapshot.QueryGetSnapshot.execute(conn, source_uuid)
  end

  def record_snapshot(conn, source_uuid, source_version, data, metadata) do
    Snapshot.RecordSnapshot.execute(conn, source_uuid, source_version, data, metadata)
  end

  defmodule QueryGetSnapshot do
    def execute(conn, source_uuid) do
      conn
      |> Postgrex.query(Statements.query_get_snapshot, [source_uuid])
      |> handle_response
    end

    defp handle_response({:ok, %Postgrex.Result{num_rows: 0}}) do
      {:error, :snapshot_not_found}
    end

    defp handle_response({:ok, %Postgrex.Result{rows: [row]}}) do
      {:ok, to_snapshot_from_row(row)}
    end

    defp to_snapshot_from_row([source_uuid, source_version, data, metadata, created_at]) do
      %Snapshot{
        source_uuid: source_uuid,
        source_version: source_version,
        data: data,
        metadata: metadata,
        created_at: created_at
      }
    end
  end

  defmodule RecordSnapshot do
    def execute(conn, source_uuid, source_version, data, metadata) do
      conn
      |> Postgrex.query(Statements.record_snapshot, [source_uuid, source_version, data, metadata])
      |> handle_response(source_uuid, source_version)
    end

    defp handle_response({:ok, _result}, _source_uuid, _source_version) do
      :ok
    end

    defp handle_response({:error, error}, source_uuid, source_version) do
      Logger.warn "failed to record snapshot for source \"#{source_uuid}\" at version \"#{source_version}\" due to: #{inspect error}"
      {:error, error}
    end
  end
end
