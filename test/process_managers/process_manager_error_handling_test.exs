defmodule Commanded.ProcessManager.ProcessManagerErrorHandlingTest do
  use Commanded.StorageCase

  alias Commanded.Helpers.ProcessHelper
  alias Commanded.ProcessManagers.{
    DefaultErrorHandlingProcessManager,
    ErrorHandlingProcessManager,
    ErrorRouter,
  }
  alias Commanded.ProcessManagers.ErrorAggregate.Commands.StartProcess

  setup do
    reply_to = self()
    {:ok, agent} = Agent.start_link(fn -> reply_to end, name: {:global, ErrorHandlingProcessManager})

    on_exit fn ->
      ProcessHelper.shutdown(agent)
    end
  end

  test "should retry the event until process manager requests stop" do
    process_uuid = UUID.uuid4()
    command = %StartProcess{
      process_uuid: process_uuid,
      strategy: "retry",
      reply_to: reply_to(),
    }

    {:ok, process_router} = ErrorHandlingProcessManager.start_link()

    Process.unlink(process_router)
    ref = Process.monitor(process_router)

    assert :ok = ErrorRouter.dispatch(command)

    assert_receive {:error, :failed, %{attempts: 1}}
    assert_receive {:error, :failed, %{attempts: 2}}
    assert_receive {:error, :too_many_attempts, %{attempts: 3}}

    # should shutdown process router
    assert_receive {:DOWN, ^ref, :process, ^process_router, :too_many_attempts}
  end

  test "should retry event with specified delay between attempts" do
    process_uuid = UUID.uuid4()
    command = %StartProcess{
      process_uuid: process_uuid,
      strategy: "retry",
      delay: 10,
      reply_to: reply_to(),
    }

    {:ok, process_router} = ErrorHandlingProcessManager.start_link()

    Process.unlink(process_router)
    ref = Process.monitor(process_router)

    assert :ok = ErrorRouter.dispatch(command)

    assert_receive {:error, :failed, %{attempts: 1, delay: 10}}
    assert_receive {:error, :failed, %{attempts: 2, delay: 10}}
    assert_receive {:error, :too_many_attempts, %{attempts: 3}}

    # should shutdown process router
    assert_receive {:DOWN, ^ref, :process, ^process_router, :too_many_attempts}
  end

  test "should skip the event when error reply is `{:skip, :continue_pending}`" do
    process_uuid = UUID.uuid4()
    command = %StartProcess{
      process_uuid: process_uuid,
      strategy: "skip",
      reply_to: reply_to(),
    }

    {:ok, process_router} = ErrorHandlingProcessManager.start_link()

    assert :ok = ErrorRouter.dispatch(command)

    assert_receive {:error, :failed, %{attempts: 1}}
    refute_receive {:error, :failed, %{attempts: 2}}

    # should not shutdown process router
    assert Process.alive?(process_router)
  end

  test "should continue with modified command" do
    process_uuid = UUID.uuid4()
    command = %StartProcess{
      process_uuid: process_uuid,
      strategy: "continue",
      reply_to: reply_to(),
    }

    {:ok, process_router} = ErrorHandlingProcessManager.start_link()

    assert :ok = ErrorRouter.dispatch(command)

    assert_receive {:error, :failed, %{attempts: 1}}
    assert_receive :process_continued

    # should not shutdown process router
    assert Process.alive?(process_router)
  end

  test "should stop process manager on error by default" do
    process_uuid = UUID.uuid4()
    command = %StartProcess{process_uuid: process_uuid}

    {:ok, process_router} = DefaultErrorHandlingProcessManager.start_link()

    Process.unlink(process_router)
    ref = Process.monitor(process_router)

    assert :ok = ErrorRouter.dispatch(command)

    # should shutdown process router
    assert_receive {:DOWN, ^ref, :process, ^process_router, :failed}
    refute Process.alive?(process_router)
  end

  defp reply_to, do: self() |> :erlang.pid_to_list()
end
