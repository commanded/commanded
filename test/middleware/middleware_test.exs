defmodule Commanded.Commands.Middleware.MiddlewareTest do
  use Commanded.StorageCase

  import Commanded.Enumerable

  alias Commanded.Commands.ExecutionResult
  alias Commanded.Middleware.Pipeline
  alias Commanded.Helpers.CommandAuditMiddleware
  alias Commanded.Helpers.Commands.{
    IncrementCount,
    Fail,
    RaiseError,
    Timeout,
    CommandHandler,
    CounterAggregateRoot,
  }

  defmodule FirstMiddleware do
    @behaviour Commanded.Middleware

    def before_dispatch(pipeline), do: pipeline
    def after_dispatch(pipeline), do: pipeline
    def after_failure(pipeline), do: pipeline
  end

  defmodule ModifyMetadataMiddleware do
    @behaviour Commanded.Middleware

    def before_dispatch(pipeline) do
      pipeline
      |> Pipeline.assign_metadata("updated_by", "ModifyMetadataMiddleware")
    end

    def after_dispatch(pipeline), do: pipeline
    def after_failure(pipeline), do: pipeline
  end

  defmodule LastMiddleware do
    @behaviour Commanded.Middleware

    def before_dispatch(pipeline), do: pipeline
    def after_dispatch(pipeline), do: pipeline
    def after_failure(pipeline), do: pipeline
  end

  defmodule Router do
    use Commanded.Commands.Router

    middleware FirstMiddleware
    middleware ModifyMetadataMiddleware
    middleware Commanded.Middleware.Logger
    middleware CommandAuditMiddleware
    middleware LastMiddleware

    dispatch [
      IncrementCount,
      Fail,
      RaiseError,
      Timeout,
    ], to: CommandHandler, aggregate: CounterAggregateRoot, identity: :aggregate_uuid
  end

  setup do
    CommandAuditMiddleware.start_link()
    CommandAuditMiddleware.reset()
  end

  test "should call middleware for each command dispatch" do
    aggregate_uuid = UUID.uuid4

    :ok = Router.dispatch(%IncrementCount{aggregate_uuid: aggregate_uuid, by: 1})
    :ok = Router.dispatch(%IncrementCount{aggregate_uuid: aggregate_uuid, by: 2})
    :ok = Router.dispatch(%IncrementCount{aggregate_uuid: aggregate_uuid, by: 3})

    {dispatched, succeeded, failed} = CommandAuditMiddleware.count_commands()

    assert dispatched == 3
    assert succeeded == 3
    assert failed == 0

    dispatched_commands = CommandAuditMiddleware.dispatched_commands()
    succeeded_commands = CommandAuditMiddleware.succeeded_commands()

    assert pluck(dispatched_commands, :by) == [1, 2, 3]
    assert pluck(succeeded_commands, :by) == [1, 2, 3]
  end

  test "should execute middleware failure callback when aggregate process returns an error tagged tuple" do
    # force command handling to return an error
    {:error, :failed} = Router.dispatch(%Fail{aggregate_uuid: UUID.uuid4})

    {dispatched, succeeded, failed} = CommandAuditMiddleware.count_commands()

    assert dispatched == 1
    assert succeeded == 0
    assert failed == 1
  end

  test "should execute middleware failure callback when aggregate process errors" do
    # force command handling to error
    {:error, :aggregate_execution_failed} = Router.dispatch(%RaiseError{aggregate_uuid: UUID.uuid4})

    {dispatched, succeeded, failed} = CommandAuditMiddleware.count_commands()

    assert dispatched == 1
    assert succeeded == 0
    assert failed == 1
  end

  test "should execute middleware failure callback when aggregate process dies" do
    # force command handling to timeout so the aggregate process is terminated
    :ok = case Router.dispatch(%Timeout{aggregate_uuid: UUID.uuid4}, 50) do
      {:error, :aggregate_execution_timeout} -> :ok
      {:error, :aggregate_execution_failed} -> :ok
    end

    {dispatched, succeeded, failed} = CommandAuditMiddleware.count_commands()

    assert dispatched == 1
    assert succeeded == 0
    assert failed == 1
  end

  test "should let a middleware update the metadata" do
    {:ok, %ExecutionResult{metadata: metadata}} =
      Router.dispatch(
        %IncrementCount{aggregate_uuid: UUID.uuid4, by: 1},
        include_execution_result: true,
        metadata: %{"first_metadata" => "first_metadata"}
      )

    assert metadata == %{
      "first_metadata" => "first_metadata",
      "updated_by" => "ModifyMetadataMiddleware"
    }
  end
end
