defmodule Commanded.Extensions.Process do
  use ExUnit.Case

  @doc """
  Stop the given process with a non-normal exit reason
  """
  def shutdown(pid) do
    Process.unlink(pid)
    Process.exit(pid, :shutdown)

    ref = Process.monitor(pid)
    assert_receive {:DOWN, ^ref, _, _, _}
  end
end
