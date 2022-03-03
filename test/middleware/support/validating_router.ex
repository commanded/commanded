defmodule Commanded.ValidatingRouter do
  use Commanded.Commands.Router

  alias Commanded.Helpers.CommandAuditMiddleware
  alias Commanded.Middleware.Commands.{CommandHandler, CounterAggregateRoot, Validate}
  alias Commanded.ValidationMiddleware

  middleware CommandAuditMiddleware
  middleware ValidationMiddleware

  dispatch Validate,
    to: CommandHandler,
    aggregate: CounterAggregateRoot,
    identity: :aggregate_uuid
end
