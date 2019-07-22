defmodule Commanded.ValidatingRouter do
  use Commanded.Commands.Router

  alias Commanded.Helpers.CommandAuditMiddleware
  alias Commanded.ValidationMiddleware
  alias Commanded.Middleware.Commands.CommandHandler
  alias Commanded.Middleware.Commands.CounterAggregateRoot
  alias Commanded.Middleware.Commands.Validate

  middleware CommandAuditMiddleware
  middleware ValidationMiddleware

  dispatch Validate,
    to: CommandHandler,
    aggregate: CounterAggregateRoot,
    identity: :aggregate_uuid
end
