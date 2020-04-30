defmodule Commanded.Middleware.MiddlewareTest do
  use ExUnit.Case

  import Commanded.Enumerable

  alias Commanded.DefaultApp
  alias Commanded.Commands.ExecutionResult
  alias Commanded.Middleware.Pipeline
  alias Commanded.Helpers.CommandAuditMiddleware

  alias Commanded.Middleware.Commands.{
    IncrementCount,
    Fail,
    RaiseError,
    Timeout,
    CommandHandler,
    CounterAggregateRoot
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
      Pipeline.assign_metadata(pipeline, "updated_by", "ModifyMetadataMiddleware")
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
               Timeout
             ],
             to: CommandHandler,
             aggregate: CounterAggregateRoot,
             identity: :aggregate_uuid
  end

  setup do
    start_supervised!(CommandAuditMiddleware)
    start_supervised!(DefaultApp)

    :ok
  end

  test "should call middleware for each command dispatch" do
    aggregate_uuid = UUID.uuid4()

    :ok =
      Router.dispatch(%IncrementCount{aggregate_uuid: aggregate_uuid, by: 1},
        application: DefaultApp
      )

    :ok =
      Router.dispatch(%IncrementCount{aggregate_uuid: aggregate_uuid, by: 2},
        application: DefaultApp
      )

    :ok =
      Router.dispatch(%IncrementCount{aggregate_uuid: aggregate_uuid, by: 3},
        application: DefaultApp
      )

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
    {:error, :failed} =
      Router.dispatch(%Fail{aggregate_uuid: UUID.uuid4()}, application: DefaultApp)

    {dispatched, succeeded, failed} = CommandAuditMiddleware.count_commands()

    assert dispatched == 1
    assert succeeded == 0
    assert failed == 1
  end

  test "should execute middleware failure callback when aggregate process errors" do
    command = %RaiseError{aggregate_uuid: UUID.uuid4()}

    # Force command handling to error
    assert {:error, %RuntimeError{message: "failed"}} =
             Router.dispatch(command, application: DefaultApp)

    {dispatched, succeeded, failed} = CommandAuditMiddleware.count_commands()

    assert dispatched == 1
    assert succeeded == 0
    assert failed == 1
  end

  test "should execute middleware failure callback when aggregate process dies" do
    command = %Timeout{aggregate_uuid: UUID.uuid4()}

    # Force command handling to timeout so the aggregate process is terminated
    :ok =
      case Router.dispatch(command, application: DefaultApp, timeout: 50) do
        {:error, :aggregate_execution_timeout} -> :ok
        {:error, :aggregate_execution_failed} -> :ok
      end

    {dispatched, succeeded, failed} = CommandAuditMiddleware.count_commands()

    assert dispatched == 1
    assert succeeded == 0
    assert failed == 1
  end

  test "should let a middleware update the metadata" do
    command = %IncrementCount{aggregate_uuid: UUID.uuid4(), by: 1}

    assert {:ok, %ExecutionResult{metadata: metadata}} =
             Router.dispatch(
               command,
               application: DefaultApp,
               include_execution_result: true,
               metadata: %{"first_metadata" => "first_metadata"}
             )

    assert metadata == %{
             "first_metadata" => "first_metadata",
             "updated_by" => "ModifyMetadataMiddleware"
           }
  end
end
