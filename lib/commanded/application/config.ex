defmodule Commanded.Application.Config do
  @moduledoc false

  use GenServer

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def associate(pid, application, value) when is_pid(pid) and is_atom(application) do
    GenServer.call(__MODULE__, {:associate, pid, application, value})
  end

  def get(application, setting) when is_atom(application) and is_atom(setting) do
    application |> lookup() |> Keyword.get(setting)
  end

  @impl GenServer
  def init(:ok) do
    table = :ets.new(__MODULE__, [:named_table, read_concurrency: true])

    {:ok, table}
  end

  @impl GenServer
  def handle_call({:associate, pid, application, config}, _from, table) do
    ref = Process.monitor(pid)
    true = :ets.insert(table, {application, pid, ref, config})

    {:reply, :ok, table}
  end

  @impl GenServer
  def handle_info({:DOWN, ref, _type, pid, _reason}, table) do
    [[application]] = :ets.match(table, {:"$1", pid, ref, :_})
    :ets.delete(table, application)

    {:noreply, table}
  end

  defp lookup(application) do
    :ets.lookup_element(__MODULE__, application, 4)
  rescue
    ArgumentError ->
      raise "could not lookup #{inspect(application)} because it was not started or it does not exist"
  end
end
