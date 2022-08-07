defmodule Commanded.Middleware.HaltingMiddlewareTest do
  use ExUnit.Case

  alias Commanded.DefaultApp
  alias Commanded.HaltingRouter
  alias Commanded.Helpers.CommandAuditMiddleware
  alias Commanded.Middleware.Commands.{IncrementCount, Validate}
  alias Commanded.UUID
  alias Commanded.ValidatingRouter

  setup do
    start_supervised!(DefaultApp)
    start_supervised!(CommandAuditMiddleware)

    :ok
  end

  test "should not dispatch the command when middleware halts pipeline" do
    command = %IncrementCount{aggregate_uuid: UUID.uuid4()}

    assert {:error, :halted} = HaltingRouter.dispatch(command, application: DefaultApp)

    {dispatched, succeeded, failed} = CommandAuditMiddleware.count_commands()

    assert dispatched == 1
    assert succeeded == 0
    assert failed == 1
  end

  test "should allow middleware to set dispatch response" do
    command = %Validate{aggregate_uuid: UUID.uuid4(), valid?: false}

    assert {:error, :validation_failure, "validation failed"} =
             ValidatingRouter.dispatch(command, application: DefaultApp)

    {dispatched, succeeded, failed} = CommandAuditMiddleware.count_commands()

    assert dispatched == 1
    assert succeeded == 0
    assert failed == 1
  end
end
