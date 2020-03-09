defmodule Commanded.Middleware.TenantApp do
  use Commanded.Application, otp_app: :commanded

  alias Commanded.Middleware.TenantRouter

  router(TenantRouter)

  def tenant_application_name(tenant_id) do
    Module.concat([__MODULE__, "tenant#{tenant_id}"])
  end
end
