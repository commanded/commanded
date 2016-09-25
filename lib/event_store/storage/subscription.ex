defmodule EventStore.Storage.Subscription do
  @moduledoc """
  Support persistent subscriptions to an event stream
  """

  require Logger

  alias EventStore.Sql.Statements
  alias EventStore.Storage.Subscription

  defstruct subscription_id: nil, stream_uuid: nil, subscription_name: nil, last_seen_event_id: nil, last_seen_stream_version: nil, created_at: nil

  @doc """
  List all known subscriptions
  """
  def subscriptions(conn) do
    Subscription.All.execute(conn)
  end

  def subscribe_to_stream(conn, stream_uuid, subscription_name) do
    case Subscription.Query.execute(conn, stream_uuid, subscription_name) do
      {:ok, subscription} -> {:ok, subscription}
      {:error, :subscription_not_found} -> Subscription.Subscribe.execute(conn, stream_uuid, subscription_name)
    end
  end

  def ack_last_seen_event(conn, stream_uuid, subscription_name, last_seen_event_id, last_seen_stream_version) do
    Subscription.Ack.execute(conn, stream_uuid, subscription_name, last_seen_event_id, last_seen_stream_version)
  end

  def unsubscribe_from_stream(conn, stream_uuid, subscription_name) do
    Subscription.Unsubscribe.execute(conn, stream_uuid, subscription_name)
  end

  defmodule All do
    def execute(conn) do
      conn
      |> Postgrex.query(Statements.query_all_subscriptions, [])
      |> handle_response
    end

    defp handle_response({:ok, %Postgrex.Result{num_rows: 0}}) do
      {:ok, []}
    end

    defp handle_response({:ok, %Postgrex.Result{rows: rows}}) do
      {:ok, Subscription.Adapter.to_subscriptions(rows)}
    end
  end

  defmodule Query do
    def execute(conn, stream_uuid, subscription_name) do
      conn
      |> Postgrex.query(Statements.query_get_subscription, [stream_uuid, subscription_name])
      |> handle_response
    end

    defp handle_response({:ok, %Postgrex.Result{num_rows: 0}}) do
      {:error, :subscription_not_found}
    end

    defp handle_response({:ok, %Postgrex.Result{rows: rows}}) do
      {:ok, Subscription.Adapter.to_subscription(rows)}
    end
  end

  defmodule Subscribe do
    def execute(conn, stream_uuid, subscription_name) do
      Logger.debug(fn -> "attempting to create subscription on stream \"#{stream_uuid}\" named \"#{subscription_name}\"" end)

      conn
      |> Postgrex.query(Statements.create_subscription, [stream_uuid, subscription_name])
      |> handle_response(stream_uuid, subscription_name)
    end

    defp handle_response({:ok, %Postgrex.Result{rows: rows}}, stream_uuid, subscription_name) do
      Logger.debug(fn -> "created subscription on stream \"#{stream_uuid}\" named \"#{subscription_name}\"" end)
      {:ok, Subscription.Adapter.to_subscription(rows)}
    end

    defp handle_response({:error, %Postgrex.Error{postgres: %{code: :unique_violation}}}, stream_uuid, subscription_name) do
      Logger.warn(fn -> "failed to create subscription on stream #{stream_uuid} named #{subscription_name}, already exists" end)
      {:error, :subscription_already_exists}
    end

    defp handle_response({:error, error}, stream_uuid, subscription_name) do
      Logger.warn(fn -> "failed to create stream create subscription on stream \"#{stream_uuid}\" named \"#{subscription_name}\" due to: #{error}" end)
      {:error, error}
    end
  end

  defmodule Ack do
    def execute(conn, stream_uuid, subscription_name, last_seen_event_id, last_seen_stream_version) do
      conn
      |> Postgrex.query(Statements.ack_last_seen_event, [stream_uuid, subscription_name, last_seen_event_id, last_seen_stream_version])
      |> handle_response(stream_uuid, subscription_name)
    end

    defp handle_response({:ok, _result}, _stream_uuid, _subscription_name) do
      :ok
    end

    defp handle_response({:error, error}, stream_uuid, subscription_name) do
      Logger.warn(fn -> "failed to ack last seen event on stream \"#{stream_uuid}\" named \"#{subscription_name}\" due to: #{error}" end)
      {:error, error}
    end
  end

  defmodule Unsubscribe do
    def execute(conn, stream_uuid, subscription_name) do
      Logger.debug(fn -> "attempting to unsubscribe from stream \"#{stream_uuid}\" named \"#{subscription_name}\"" end)

      conn
      |> Postgrex.query(Statements.delete_subscription, [stream_uuid, subscription_name])
      |> handle_response(stream_uuid, subscription_name)
    end

    defp handle_response({:ok, _result}, stream_uuid, subscription_name) do
      Logger.debug(fn -> "unsubscribed from stream \"#{stream_uuid}\" named \"#{subscription_name}\"" end)
      :ok
    end

    defp handle_response({:error, error}, stream_uuid, subscription_name) do
      Logger.warn(fn -> "failed to unsubscribe from stream \"#{stream_uuid}\" named \"#{subscription_name}\" due to: #{error}" end)
      {:error, error}
    end
  end

  defmodule Adapter do
    def to_subscriptions(rows) do
      rows
      |> Enum.map(&to_subscription_from_row/1)
    end

    def to_subscription(rows) do
      rows
      |> List.first
      |> to_subscription_from_row
    end

    defp to_subscription_from_row([subscription_id, stream_uuid, subscription_name, last_seen_event_id, last_seen_stream_version, created_at]) do
      %Subscription{
        subscription_id: subscription_id,
        stream_uuid: stream_uuid,
        subscription_name: subscription_name,
        last_seen_event_id: last_seen_event_id,
        last_seen_stream_version: last_seen_stream_version,
        created_at: created_at
      }
    end
  end
end
