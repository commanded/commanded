defmodule EventStore.ProcessHelper do
  import ExUnit.Assertions

  @doc """
  Stop the given process with a non-normal exit reason
  """
  def shutdown(name) when is_atom(name) do
    name |> Process.whereis() |> shutdown()
  end

  def shutdown(pid) when is_pid(pid) do
    Process.unlink(pid)
    Process.exit(pid, :shutdown)

    ref = Process.monitor(pid)
    assert_receive {:DOWN, ^ref, _, _, _}, 1_000
  end
end
