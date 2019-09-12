defmodule Commanded.Application.Config do
  @moduledoc false

  use GenServer

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def associate(pid, value) when is_pid(pid) do
    GenServer.call(__MODULE__, {:associate, pid, value})
  end

  def get(application, setting) do
    application |> lookup() |> Keyword.get(setting)
  end

  @impl GenServer
  def init(:ok) do
    table = :ets.new(__MODULE__, [:named_table, read_concurrency: true])

    {:ok, table}
  end

  @impl GenServer
  def handle_call({:associate, pid, value}, _from, table) do
    ref = Process.monitor(pid)
    true = :ets.insert(table, {pid, ref, value})

    {:reply, :ok, table}
  end

  @impl GenServer
  def handle_info({:DOWN, ref, _type, pid, _reason}, table) do
    [{^pid, ^ref, _}] = :ets.lookup(table, pid)
    :ets.delete(table, pid)

    {:noreply, table}
  end

  defp lookup(application) when is_atom(application) do
    case GenServer.whereis(application) do
      pid when is_pid(pid) ->
        lookup(pid)

      nil ->
        raise "could not lookup #{inspect(application)} because it was not started or it does not exist"
    end
  end

  defp lookup(pid) when is_pid(pid) do
    :ets.lookup_element(__MODULE__, pid, 3)
  end
end
