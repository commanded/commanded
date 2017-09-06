defmodule Commanded.Helpers.Process do
  @moduledoc false
  import ExUnit.Assertions

  use Commanded.Registration

  alias Commanded.Aggregates.Aggregate

  @doc """
  Stop the given process with a non-normal exit reason
  """
  def shutdown(pid) when is_pid(pid) do
    Process.unlink(pid)
    Process.exit(pid, :shutdown)

    ref = Process.monitor(pid)
    assert_receive {:DOWN, ^ref, _, _, _}, 5_000
  end

  def shutdown(name) when is_atom(name) do
    case Process.whereis(name) do
      nil -> :ok
      pid -> shutdown(pid)
    end
  end

  def shutdown(aggregate_module, aggregate_uuid) do
    pid = @registry.whereis_name({aggregate_module, aggregate_uuid})
    shutdown(pid)
  end
end
