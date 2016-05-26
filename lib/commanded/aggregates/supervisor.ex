defmodule Commanded.Aggregates.Supervisor do
  @moduledoc """
  Supervise zero, one or more event sourced aggregates
  """

  use Supervisor
  require Logger

  def start_link do
    Supervisor.start_link(__MODULE__, nil)
  end

  def start_aggregate(supervisor, aggregate_module, aggregate_id) do
    Logger.debug(fn -> "starting aggregate process for `#{aggregate_module}` with id #{aggregate_id}" end)

    Supervisor.start_child(supervisor, [aggregate_module, aggregate_id])
  end

  def init(_) do
    children = [
      worker(Commanded.Aggregates.Aggregate, [], restart: :transient),
    ]

    supervise(children, strategy: :simple_one_for_one)
  end
end
