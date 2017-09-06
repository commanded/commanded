defmodule Commanded.Helpers.Process do
  @moduledoc false
  import ExUnit.Assertions

  alias Commanded.Aggregates.Aggregate
  alias Commanded.Registration

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

  def shutdown(module, uuid),
    do: {module, uuid} |> Registration.whereis_name() |> shutdown()
end
