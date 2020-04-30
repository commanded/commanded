defmodule Commanded.Middleware.ApplicationMiddlewareTest do
  use ExUnit.Case

  alias Commanded.Middleware.Tenant.Commands.RegisterTenant
  alias Commanded.Middleware.TenantApp

  setup do
    for tenant_id <- 1..3 do
      start_supervised!({TenantApp, name: TenantApp.tenant_application_name(tenant_id)})
    end

    :ok
  end

  test "dispatch command to dynamic application set in middleware" do
    for tenant_id <- 1..3 do
      command = %RegisterTenant{tenant_id: tenant_id, name: "Tenant #{tenant_id}"}

      assert :ok = TenantApp.dispatch(command)

      name = TenantApp.tenant_application_name(tenant_id)
      pid = Process.whereis(name)
      assert is_pid(pid)
    end
  end

  test "raise `RuntimeError` when application not started" do
    command = %RegisterTenant{tenant_id: 4, name: "Tenant 4"}

    assert_raise RuntimeError, fn ->
      :ok = TenantApp.dispatch(command)
    end
  end
end
