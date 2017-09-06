defmodule Commanded.Aggregates.Supervisor do
  @moduledoc """
  Supervises `Commanded.Aggregates.Aggregate` instance processes
  """

  use Supervisor

  require Logger

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @doc """
  Open an aggregate instance process for the given aggregate module and unique indentity

  Returns `{:ok, aggregate_uuid}` when a process is sucessfully started, or is already running.
  """
  def open_aggregate(aggregate_module, aggregate_uuid)
  def open_aggregate(aggregate_module, aggregate_uuid)
    when is_integer(aggregate_uuid) or
         is_atom(aggregate_uuid) or
         is_bitstring(aggregate_uuid) do

    Logger.debug(fn -> "Locating aggregate process for `#{inspect aggregate_module}` with UUID #{inspect aggregate_uuid}" end)

    case Supervisor.start_child(__MODULE__, [aggregate_module, aggregate_uuid]) do
      {:ok, _pid} -> {:ok, aggregate_uuid}
      {:ok, _pid, _info} -> {:ok, aggregate_uuid}
      {:error, {:already_started, _pid}} -> {:ok, aggregate_uuid}
      reply -> reply
    end
  end

  def init(_) do
    children = [
      worker(Commanded.Aggregates.Aggregate, [], restart: :temporary),
    ]

    supervise(children, strategy: :simple_one_for_one)
  end
end
