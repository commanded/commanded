defmodule Commanded.ProcessManager.ProcessManagerInitTest do
  use ExUnit.Case

  alias Commanded.DefaultApp
  alias Commanded.ProcessManagers.RuntimeConfigProcessManager

  describe "process manager `init/1` callback" do
    setup do
      for tenant <- [:tenant1, :tenant2, :tenant3] do
        start_supervised!({DefaultApp, name: Module.concat([DefaultApp, tenant])})
      end

      :ok
    end

    test "should be called at runtime" do
      {:ok, _pm1} = RuntimeConfigProcessManager.start_link(tenant: :tenant1, reply_to: self())
      {:ok, _pm2} = RuntimeConfigProcessManager.start_link(tenant: :tenant2, reply_to: self())
      {:ok, _pm3} = RuntimeConfigProcessManager.start_link(tenant: :tenant3, reply_to: self())

      assert_receive {:init, :tenant1}
      assert_receive {:init, :tenant2}
      assert_receive {:init, :tenant3}
    end

    test "should be called on restart if the process crashes" do
      pm = start_supervised!({RuntimeConfigProcessManager, tenant: :tenant1, reply_to: self()})

      Process.exit(pm, :kill)

      assert_receive {:init, :tenant1}
      assert_receive {:init, :tenant1}
      refute_receive {:init, :tenant1}
    end
  end
end
