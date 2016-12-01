defmodule Commanded.Commands.Middleware.HaltingMiddlewareTest do
  use Commanded.StorageCase

  alias Commanded.Helpers.CommandAuditMiddleware
  alias Commanded.Helpers.Commands.{IncrementCount,Validate,CommandHandler,CounterAggregateRoot}

  defmodule HaltingMiddleware do
    @behaviour Commanded.Middleware

    import Commanded.Middleware.Pipeline

    def before_dispatch(pipeline), do: halt(pipeline)
    def after_dispatch(pipeline), do: pipeline
    def after_failure(pipeline), do: pipeline
  end

  defmodule ValidationMiddleware do
    @behaviour Commanded.Middleware

    alias Commanded.Middleware.Pipeline
    import Pipeline

    def before_dispatch(%Pipeline{command: command} = pipeline) do
      case Map.get(command, :valid?, false) do
        true -> pipeline
        false ->
          pipeline
          |> respond({:error, :validation_failure})
          |> halt
      end
    end

    def after_dispatch(pipeline), do: pipeline
    def after_failure(pipeline), do: pipeline
  end

  defmodule HaltingRouter do
    use Commanded.Commands.Router

    middleware CommandAuditMiddleware
    middleware HaltingMiddleware

    dispatch IncrementCount, to: CommandHandler, aggregate: CounterAggregateRoot, identity: :aggregate_uuid
  end

  defmodule ValidatingRouter do
    use Commanded.Commands.Router

    middleware CommandAuditMiddleware
    middleware ValidationMiddleware

    dispatch Validate, to: CommandHandler, aggregate: CounterAggregateRoot, identity: :aggregate_uuid
  end

  test "should not dispatch the command when middleware halts pipeline" do
    {:ok, _} = CommandAuditMiddleware.start_link

    {:error, :halted} = HaltingRouter.dispatch(%IncrementCount{aggregate_uuid: UUID.uuid4})

    {dispatched, succeeded, failed} = CommandAuditMiddleware.count_commands

    assert dispatched == 1
    assert succeeded == 0
    assert failed == 1
  end

  test "should allow middleware to set dispatch response" do
    {:ok, _} = CommandAuditMiddleware.start_link

    {:error, :validation_failure} = ValidatingRouter.dispatch(%Validate{aggregate_uuid: UUID.uuid4, valid?: false})

    {dispatched, succeeded, failed} = CommandAuditMiddleware.count_commands

    assert dispatched == 1
    assert succeeded == 0
    assert failed == 1
  end
end
