defmodule Commanded.HaltingRouter do
  use Commanded.Commands.Router

  alias Commanded.Helpers.CommandAuditMiddleware
  alias Commanded.HaltingMiddleware
  alias Commanded.Middleware.Commands.CommandHandler
  alias Commanded.Middleware.Commands.CounterAggregateRoot
  alias Commanded.Middleware.Commands.IncrementCount

  middleware CommandAuditMiddleware
  middleware HaltingMiddleware

  dispatch IncrementCount,
    to: CommandHandler,
    aggregate: CounterAggregateRoot,
    identity: :aggregate_uuid
end
