defmodule Commanded.ProcessManagers.ProcessManagerInstanceExceptionTest do
  use Commanded.StorageCase

  alias Commanded.ProcessManagers.{ExampleRouter, ExampleProcessManager}
  alias Commanded.ProcessManagers.ExampleAggregate.Commands.{Error, Raise, Start}

  test "should stop process router when handling event errors" do
    aggregate_uuid = UUID.uuid4()

    {:ok, process_router} = ExampleProcessManager.start_link()

    Process.unlink(process_router)
    ref = Process.monitor(process_router)

    :ok = ExampleRouter.dispatch(%Start{aggregate_uuid: aggregate_uuid})
    :ok = ExampleRouter.dispatch(%Error{aggregate_uuid: aggregate_uuid})

    # Should shutdown process
    assert_receive {:DOWN, ^ref, _, _, _}
  end

  test "should stop process router when handling event exception" do
    aggregate_uuid = UUID.uuid4()

    {:ok, process_router} = ExampleProcessManager.start_link()

    Process.unlink(process_router)
    ref = Process.monitor(process_router)

    :ok = ExampleRouter.dispatch(%Start{aggregate_uuid: aggregate_uuid})
    :ok = ExampleRouter.dispatch(%Raise{aggregate_uuid: aggregate_uuid})

    # Should shutdown process
    assert_receive {:DOWN, ^ref, _, _, _}
  end
end
