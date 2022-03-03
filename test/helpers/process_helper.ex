defmodule Commanded.Helpers.ProcessHelper do
  @moduledoc false

  import ExUnit.Assertions

  alias Commanded.Helpers.Wait
  alias Commanded.Registration

  @doc """
  Stop the given process with a non-normal exit reason.
  """
  def shutdown(pid, reason \\ :shutdown)

  def shutdown(pid, reason) when is_pid(pid) do
    Process.unlink(pid)
    Process.exit(pid, reason)

    ref = Process.monitor(pid)
    assert_receive {:DOWN, ^ref, _, _, _}, 5_000
  end

  def shutdown(name, reason) when is_atom(name) do
    case Process.whereis(name) do
      nil -> :ok
      pid -> shutdown(pid, reason)
    end
  end

  @doc """
  Stop a given aggregate process.
  """
  def shutdown_aggregate(application, aggregate_module, aggregate_uuid) do
    name = {application, aggregate_module, aggregate_uuid}

    Registration.whereis_name(application, name) |> shutdown()

    # Wait until process removed from registry
    Wait.until(fn ->
      assert Registration.whereis_name(application, name) == :undefined
    end)
  end
end
