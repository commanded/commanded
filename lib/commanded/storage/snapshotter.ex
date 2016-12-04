defmodule Commanded.Storage.Snapshotter do
  @moduledoc """
  Receives an async message with the state to store snapshots.
  """
  use GenServer

  ### Api

  @doc "Starts the snapshotter"
  def start_link, do:
    GenServer.start_link(__MODULE__, :ok, [])

  @doc "Append snapshot"
  def send_snapshot(server, state), do:
    GenServer.cast(server, {:state, state})

  ### Server Callbacks

  def init(:ok), do:
    {:ok, %{}}

  def handle_cast({:state, state}, _from, names), do:
    {:reply, state}

end
