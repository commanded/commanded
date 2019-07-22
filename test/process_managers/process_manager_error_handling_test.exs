defmodule Commanded.ProcessManager.ProcessManagerErrorHandlingTest do
  use Commanded.StorageCase

  alias Commanded.ProcessManagers.DefaultErrorHandlingProcessManager
  alias Commanded.ProcessManagers.ErrorApp
  alias Commanded.ProcessManagers.ErrorHandlingProcessManager
  alias Commanded.ProcessManagers.ErrorRouter
  alias Commanded.ProcessManagers.ErrorAggregate.Commands.RaiseError
  alias Commanded.ProcessManagers.ErrorAggregate.Commands.RaiseException
  alias Commanded.ProcessManagers.ErrorAggregate.Commands.StartProcess

  setup do
    start_supervised!(ErrorApp)

    :ok
  end

  describe "process manager event handling error" do
    test "should call `error/3` callback on error" do
      {:ok, process_router} = ErrorHandlingProcessManager.start_link()

      command = %RaiseError{
        process_uuid: UUID.uuid4(),
        message: "an error",
        reply_to: reply_to()
      }

      ref = Process.monitor(process_router)

      assert :ok = ErrorRouter.dispatch(command, application: ErrorApp)

      assert_receive {:error, "an error"}
      refute_receive {:DOWN, ^ref, _, _, _}
    end

    test "should call `error/3` callback on exception" do
      {:ok, process_router} = ErrorHandlingProcessManager.start_link()

      command = %RaiseException{
        process_uuid: UUID.uuid4(),
        message: "an exception",
        reply_to: reply_to()
      }

      ref = Process.monitor(process_router)

      assert :ok = ErrorRouter.dispatch(command, application: ErrorApp)

      assert_receive {:error, %RuntimeError{message: "an exception"}}
      refute_receive {:DOWN, ^ref, _, _, _}
    end
  end

  describe "process manager dispatch command error" do
    test "should retry the event until process manager requests stop" do
      {:ok, process_router} = ErrorHandlingProcessManager.start_link()

      command = %StartProcess{
        process_uuid: UUID.uuid4(),
        strategy: "retry",
        reply_to: reply_to()
      }

      Process.unlink(process_router)
      ref = Process.monitor(process_router)

      assert :ok = ErrorRouter.dispatch(command, application: ErrorApp)

      assert_receive {:error, :failed, %{attempts: 1}}
      assert_receive {:error, :failed, %{attempts: 2}}
      assert_receive {:error, :too_many_attempts, %{attempts: 3}}

      # should shutdown process router
      assert_receive {:DOWN, ^ref, :process, ^process_router, :too_many_attempts}
    end

    test "should retry command with specified delay between attempts" do
      command = %StartProcess{
        process_uuid: UUID.uuid4(),
        strategy: "retry",
        delay: 10,
        reply_to: reply_to()
      }

      {:ok, process_router} = ErrorHandlingProcessManager.start_link()

      Process.unlink(process_router)
      ref = Process.monitor(process_router)

      assert :ok = ErrorRouter.dispatch(command, application: ErrorApp)

      assert_receive {:error, :failed, %{attempts: 1, delay: 10}}
      assert_receive {:error, :failed, %{attempts: 2, delay: 10}}
      assert_receive {:error, :too_many_attempts, %{attempts: 3}}

      # Should shutdown process router
      assert_receive {:DOWN, ^ref, :process, ^process_router, :too_many_attempts}
    end

    test "should skip the event when error reply is `{:skip, :continue_pending}`" do
      command = %StartProcess{
        process_uuid: UUID.uuid4(),
        strategy: "skip",
        reply_to: reply_to()
      }

      {:ok, process_router} = ErrorHandlingProcessManager.start_link()

      assert :ok = ErrorRouter.dispatch(command, application: ErrorApp)

      assert_receive {:error, :failed, %{attempts: 1}}
      refute_receive {:error, :failed, %{attempts: 2}}

      # Should not shutdown process router
      assert Process.alive?(process_router)
    end

    test "should continue with modified command" do
      command = %StartProcess{
        process_uuid: UUID.uuid4(),
        strategy: "continue",
        reply_to: reply_to()
      }

      {:ok, process_router} = ErrorHandlingProcessManager.start_link()

      assert :ok = ErrorRouter.dispatch(command, application: ErrorApp)

      assert_receive {:error, :failed, %{attempts: 1}}
      assert_receive :process_continued

      # Should not shutdown process router
      assert Process.alive?(process_router)
    end

    test "should stop process manager on error by default" do
      command = %StartProcess{process_uuid: UUID.uuid4(), reply_to: reply_to()}

      {:ok, process_router} = DefaultErrorHandlingProcessManager.start_link()

      Process.unlink(process_router)
      ref = Process.monitor(process_router)

      assert :ok = ErrorRouter.dispatch(command, application: ErrorApp)

      # Should shutdown process router
      assert_receive {:DOWN, ^ref, :process, ^process_router, :failed}
      refute Process.alive?(process_router)
    end
  end

  defp reply_to, do: :erlang.pid_to_list(self())
end
