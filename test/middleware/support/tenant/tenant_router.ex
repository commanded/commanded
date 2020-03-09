defmodule Commanded.Middleware.TenantRouter do
  use Commanded.Commands.Router

  alias Commanded.Middleware.Tenant
  alias Commanded.Middleware.Tenant.Commands.RegisterTenant
  alias Commanded.Middleware.TenantMiddleware

  middleware(TenantMiddleware)

  dispatch(RegisterTenant, to: Tenant, identity: :tenant_id)
end
