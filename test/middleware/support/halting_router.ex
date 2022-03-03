defmodule Commanded.HaltingRouter do
  use Commanded.Commands.Router

  alias Commanded.HaltingMiddleware
  alias Commanded.Helpers.CommandAuditMiddleware
  alias Commanded.Middleware.Commands.{CommandHandler, CounterAggregateRoot, IncrementCount}

  middleware CommandAuditMiddleware
  middleware HaltingMiddleware

  dispatch IncrementCount,
    to: CommandHandler,
    aggregate: CounterAggregateRoot,
    identity: :aggregate_uuid
end
