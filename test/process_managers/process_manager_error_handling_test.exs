defmodule Commanded.ProcessManager.ProcessManagerErrorHandlingTest do
  use ExUnit.Case

  alias Commanded.Helpers.EventFactory
  alias Commanded.ProcessManagers.DefaultErrorHandlingProcessManager
  alias Commanded.ProcessManagers.ErrorAggregate.Commands.StartProcess

  alias Commanded.ProcessManagers.ErrorAggregate.Events.{
    ProcessError,
    ProcessException,
    ProcessDispatchException
  }

  alias Commanded.ProcessManagers.ErrorApp
  alias Commanded.ProcessManagers.ErrorHandlingProcessManager
  alias Commanded.ProcessManagers.ErrorRouter

  alias Commanded.ProcessManagers.FailureContext

  setup do
    start_supervised!(ErrorApp)

    {:ok, process_router} = ErrorHandlingProcessManager.start_link()

    Process.unlink(process_router)
    ref = Process.monitor(process_router)

    [process_router: process_router, ref: ref]
  end

  describe "process manager event handling exception" do
    test "should print the stack trace", %{process_router: process_router, ref: ref} do
      import ExUnit.CaptureLog

      send_error_message = fn ->
        send_exception_event(process_router)

        assert_receive {:DOWN, ^ref, :process, ^process_router,
                        %RuntimeError{message: "an exception"}}
      end

      captured = capture_log(send_error_message)

      assert captured =~ "(RuntimeError) an exception"
      assert captured =~ "error_handling_process_manager.ex"
      assert captured =~ "Commanded.ProcessManagers.ErrorHandlingProcessManager.handle/2"
    end

    test "should include the stack trace in failure context", %{
      process_router: process_router,
      ref: ref
    } do
      send_exception_event(process_router)

      expected_runtime_error = %RuntimeError{message: "an exception"}

      assert_receive {:error, ^expected_runtime_error, %FailureContext{stacktrace: stacktrace}}
      assert_receive {:DOWN, ^ref, :process, ^process_router, ^expected_runtime_error}

      refute is_nil(stacktrace)
    end
  end

  describe "process manager event handling error" do
    test "should call `error/3` callback on error", %{process_router: process_router, ref: ref} do
      send_error_event(process_router)

      assert_receive {:error, "an error", %FailureContext{stacktrace: stacktrace}}
      assert_receive {:DOWN, ^ref, :process, ^process_router, "an error"}

      assert is_nil(stacktrace)
    end

    test "should call `error/3` callback on exception", %{
      process_router: process_router,
      ref: ref
    } do
      send_exception_event(process_router)

      expected_runtime_error = %RuntimeError{message: "an exception"}

      assert_receive {:error, ^expected_runtime_error, _failure_context}
      assert_receive {:DOWN, ^ref, :process, ^process_router, ^expected_runtime_error}
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

      assert_receive {:error, :failed, %{attempts: 1}, _failure_context}
      assert_receive {:error, :failed, %{attempts: 2}, _failure_context}
      assert_receive {:error, :too_many_attempts, %{attempts: 3}, _failure_context}

      # Should shutdown process router
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

      assert_receive {:error, :failed, %{attempts: 1, delay: 10}, _failure_context}
      assert_receive {:error, :failed, %{attempts: 2, delay: 10}, _failure_context}
      assert_receive {:error, :too_many_attempts, %{attempts: 3}, _failure_context}

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

      assert_receive {:error, :failed, %{attempts: 1}, _failure_context}
      refute_receive {:error, :failed, %{attempts: 2}, _failure_context}

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

      assert_receive {:error, :failed, %{attempts: 1}, _failure_context}
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

  describe "process manager dispatch command exception" do
    test "should stop process manager", %{process_router: process_router, ref: ref} do
      send_dispatch_exception_event(process_router)

      expected_runtime_error = %RuntimeError{message: "a dispatch exception"}

      assert_receive {:error, ^expected_runtime_error, %FailureContext{}}
      assert_receive {:DOWN, ^ref, :process, ^process_router, ^expected_runtime_error}
    end
  end

  defp send_error_event(process_router) do
    process_uuid = UUID.uuid4()

    send_events_to_process_router(process_router, [
      %ProcessError{process_uuid: process_uuid, reply_to: reply_to(), message: "an error"}
    ])
  end

  defp send_exception_event(process_router) do
    process_uuid = UUID.uuid4()

    send_events_to_process_router(process_router, [
      %ProcessException{process_uuid: process_uuid, reply_to: reply_to(), message: "an exception"}
    ])
  end

  defp send_dispatch_exception_event(process_router) do
    process_uuid = UUID.uuid4()

    send_events_to_process_router(process_router, [
      %ProcessDispatchException{
        process_uuid: process_uuid,
        reply_to: reply_to(),
        message: "a dispatch exception"
      }
    ])
  end

  defp send_events_to_process_router(process_router, events) do
    recorded_events = EventFactory.map_to_recorded_events(events)

    send(process_router, {:events, recorded_events})
  end

  defp reply_to, do: :erlang.pid_to_list(self())
end
