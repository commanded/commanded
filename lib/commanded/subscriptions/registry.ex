defmodule Commanded.Subscriptions.Registry do
  @moduledoc false

  # Provides read/write access to a public ETS table used to track event store
  # subscriptions. This process' only use is as the owner of the ETS table and
  # should never crash.

  use GenServer

  def start_link(arg) do
    GenServer.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @doc """
  Register an event store subscription with the given consistency guarantee.
  """
  def register(name, consistency)
  def register(_name, :eventual), do: :ok
  def register(name, :strong) do
    true = :ets.insert(__MODULE__, {name, self()})

    :ok
  end

  @doc """
  Get all registered subscriptions.
  """
  def all do
    :ets.tab2list(__MODULE__)
  end

  def init(_arg) do
    table = :ets.new(__MODULE__, [:set, :public, :named_table])

    {:ok, table}
  end
end
