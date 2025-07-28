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
    pre_otp_28 = {:current_function, {:erlang, :hibernate, 3}}
    post_otp_28 = {:current_function, {:gen_server, :loop_hibernate, 4}}

    assert Process.info(pid, :current_function) in [pre_otp_28, post_otp_28]
  end
end
