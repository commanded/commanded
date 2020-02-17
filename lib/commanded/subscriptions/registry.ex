defmodule Commanded.Subscriptions.Registry do
  @moduledoc false

  # Provides read/write access to a public ETS table used to track event store
  # subscriptions. This process' only use is as the owner of the ETS table and
  # should never crash.

  use GenServer

  def start_link(opts) do
    {start_opts, registry_opts} = Keyword.split(opts, [:name, :timeout, :debug, :spawn_opt])

    GenServer.start_link(__MODULE__, registry_opts, start_opts)
  end

  @doc """
  Register an event store subscription with the given consistency guarantee.
  """
  def register(application, name, pid, consistency)

  # Ignore subscriptions with `:eventual` consistency
  def register(_application, _name, _pid, :eventual), do: :ok

  # Register subscriptions with `:strong` consistency
  def register(application, name, pid, :strong) do
    table_name = table_name(application)

    true = :ets.insert(table_name, {name, pid})

    :ok
  end

  @doc """
  Get all registered subscriptions.
  """
  def all(application) do
    application
    |> table_name()
    |> :ets.tab2list()
  end

  def init(args) do
    application = Keyword.fetch!(args, :application)

    table_name = table_name(application)
    table = :ets.new(table_name, [:set, :public, :named_table])

    {:ok, table}
  end

  defp table_name(application), do: Module.concat([application, __MODULE__])
end
