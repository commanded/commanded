defmodule Commanded.Aggregates.Supervisor do
  @moduledoc """
  Supervise zero, one or more event sourced aggregates
  """

  use Supervisor
  require Logger
  @aggregate_registry_name :aggregate_registry

  def start_link do
    Supervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  def open_aggregate(aggregate_module, aggregate_uuid)
    when is_integer(aggregate_uuid) or
         is_atom(aggregate_uuid) or
         is_bitstring(aggregate_uuid) do

    Logger.debug(fn -> "Locating aggregate process for `#{inspect aggregate_module}` with UUID #{inspect aggregate_uuid}" end)

    case Swarm.whereis_name(aggregate_uuid) do
      :undefined ->
        register(aggregate_module, aggregate_uuid)
      pid ->
        case :rpc.pinfo(pid, :status) do
          :undefined ->
            register(aggregate_module, aggregate_uuid)
          _ -> {:ok, aggregate_uuid}
        end
    end
  end

  def register(aggregate_module, aggregate_uuid) do
    case Swarm.register_name(aggregate_uuid, Commanded.Aggregates.Supervisor,
        :start_aggregate, [aggregate_module, aggregate_uuid]) do
      {:ok, pid} -> 
        Swarm.join(@aggregate_registry_name, pid)
        {:ok, aggregate_uuid}
      {:error, desc} ->
        {:error, desc}
      _ ->
        {:error, :registration_error}
      end
  end

  def start_aggregate(aggregate_module, aggregate_uuid) do
    Supervisor.start_child(__MODULE__, [aggregate_module, aggregate_uuid])
  end

  def init(_) do
    children = [
      worker(Commanded.Aggregates.Aggregate, [], restart: :temporary),
    ]

    supervise(children, strategy: :simple_one_for_one)
  end
end
