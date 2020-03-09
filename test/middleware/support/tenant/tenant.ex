defmodule Commanded.Middleware.Tenant do
  defmodule Commands do
    defmodule RegisterTenant do
      @enforce_keys [:tenant_id, :name]
      defstruct [:tenant_id, :name]
    end
  end

  defmodule Events do
    defmodule TenantRegistered do
      @derive Jason.Encoder
      defstruct [:tenant_id, :name]
    end
  end

  alias Commanded.Middleware.Tenant
  alias Commanded.Middleware.Tenant.Commands.RegisterTenant
  alias Commanded.Middleware.Tenant.Events.TenantRegistered

  defstruct [:tenant_id, :name]

  def execute(%Tenant{tenant_id: nil}, %RegisterTenant{} = command) do
    %RegisterTenant{tenant_id: tenant_id, name: name} = command

    %TenantRegistered{tenant_id: tenant_id, name: name}
  end

  def apply(%Tenant{} = tenant, %TenantRegistered{} = event) do
    %TenantRegistered{tenant_id: tenant_id, name: name} = event

    %Tenant{tenant | tenant_id: tenant_id, name: name}
  end
end
