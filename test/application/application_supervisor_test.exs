defmodule Commanded.Aggregates.ApplicationSupervisorTest do
  use ExUnit.Case

  alias Commanded.DefaultApp
  alias Commanded.Helpers.Wait

  describe "application supervisor configured with `hibernate_after`" do
    setup do
      start_supervised!({DefaultApp, hibernate_after: 1})
      :ok
    end

    test "children are hibernated after inactivity" do
      for module <- [
            Commanded.Commands.TaskDispatcher,
            Commanded.Aggregates.Supervisor,
            Commanded.Subscriptions,
            Commanded.Subscriptions.Registry
          ] do
        name = Module.concat([DefaultApp, module])
        pid = Process.whereis(name)

        assert is_pid(pid)

        Wait.until(fn -> assert_hibernated(pid) end)
      end
    end
  end

  defp assert_hibernated(pid) do
    assert Process.info(pid, :current_function) == {:current_function, {:erlang, :hibernate, 3}}
  end
end
