defmodule Commanded.Middleware.TenantMiddleware do
  @behaviour Commanded.Middleware

  alias Commanded.Middleware.Pipeline
  alias Commanded.Middleware.TenantApp

  def before_dispatch(%Pipeline{} = pipeline) do
    %Pipeline{command: command} = pipeline

    # Dynamically set application name from `tenant_id` in command
    tenant_id = Map.fetch!(command, :tenant_id)
    application = TenantApp.tenant_application_name(tenant_id)

    %Pipeline{pipeline | application: application}
  end

  def before_dispatch(pipeline), do: pipeline

  def after_dispatch(pipeline), do: pipeline
  def after_failure(pipeline), do: pipeline
end
