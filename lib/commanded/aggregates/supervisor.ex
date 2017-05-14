defmodule Commanded.Aggregates.Supervisor do
  @moduledoc """
  Supervise zero, one or more event sourced aggregates
  """

  use Supervisor
  require Logger

  def start_link do
    Supervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  def open_aggregate(aggregate_module, aggregate_uuid)
    when is_integer(aggregate_uuid) or
         is_atom(aggregate_uuid) or
         is_bitstring(aggregate_uuid) do

    Logger.debug(fn -> "starting aggregate process for `#{inspect aggregate_module}` with UUID #{inspect aggregate_uuid}" end)

    case Supervisor.start_child(__MODULE__, [aggregate_module, aggregate_uuid]) do
      {:ok, _pid} -> {:ok, aggregate_uuid}
      {:error, {:already_started, _pid}} -> {:ok, aggregate_uuid}
      other -> {:error, other}
    end
  end

  def init(_) do
    children = [
      worker(Commanded.Aggregates.Aggregate, [], restart: :temporary),
    ]

    supervise(children, strategy: :simple_one_for_one)
  end
end
