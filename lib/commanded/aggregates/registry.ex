defmodule Commanded.Aggregates.Registry do
  @moduledoc """
  Provides access to an event sourced aggregate by id
  """

  use GenServer
  require Logger

  alias Commanded.Aggregates
  alias Commanded.Aggregates.Registry

  defstruct aggregates: %{}, supervisor: nil

  def start_link do
    GenServer.start_link(__MODULE__, %Registry{}, name: __MODULE__)
  end

  def open_aggregate(aggregate_module, aggregate_uuid) do
    GenServer.call(__MODULE__, {:open_aggregate, aggregate_module, aggregate_uuid})
  end

  def init(%Registry{} = state) do
    {:ok, supervisor} = Aggregates.Supervisor.start_link

    state = %Registry{state | supervisor: supervisor}

    {:ok, state}
  end

  def handle_call({:open_aggregate, aggregate_module, aggregate_uuid}, _from, %Registry{aggregates: aggregates, supervisor: supervisor} = state) do
    aggregate = case Map.get(aggregates, aggregate_uuid) do
      nil -> start_aggregate(supervisor, aggregate_module, aggregate_uuid)
      aggregate -> aggregate
    end

    {:reply, {:ok, aggregate}, %Registry{state | aggregates: Map.put(aggregates, aggregate_uuid, aggregate)}}
  end

  def handle_info({:DOWN, _ref, :process, pid, reason}, %Registry{aggregates: aggregates} = state) do
    Logger.warn(fn -> "aggregate process down due to: #{inspect reason}" end)

    {:noreply, %Registry{state | aggregates: remove_aggregate(aggregates, pid)}}
  end

  defp start_aggregate(supervisor, aggregate_module, aggregate_uuid) do
    {:ok, aggregate} = Aggregates.Supervisor.start_aggregate(supervisor, aggregate_module, aggregate_uuid)
    Process.monitor(aggregate)
    aggregate
  end

  defp remove_aggregate(aggregates, pid) do
    Enum.reduce(aggregates, aggregates, fn
      ({aggregate_uuid, aggregate_pid}, acc) when aggregate_pid == pid -> Map.delete(acc, aggregate_uuid)
      (_, acc) -> acc
    end)
  end
end
