defmodule Commanded.Event.EventHandlerErrorHandlingTest do
  use ExUnit.Case

  alias Commanded.DefaultApp
  alias Commanded.Event.FailureContext
  alias Commanded.Event.ErrorAggregate.Events.{ErrorEvent, ExceptionEvent}
  alias Commanded.Event.ErrorEventHandler
  alias Commanded.Helpers.EventFactory

  setup do
    start_supervised!(DefaultApp)

    {:ok, handler} = ErrorEventHandler.start_link()

    Process.unlink(handler)

    [
      handler: handler,
      ref: Process.monitor(handler)
    ]
  end

  describe "event handling exception handling" do
    test "should print the stack trace", %{handler: handler, ref: ref} do
      import ExUnit.CaptureLog

      send_error_message = fn ->
        send_exception_event(handler)

        assert_receive {:DOWN, ^ref, :process, ^handler, %RuntimeError{message: "exception"}}
      end

      captured = capture_log(send_error_message)

      assert captured =~ "(RuntimeError) exception"
      assert captured =~ "error_event_handler.ex"
      assert captured =~ "Commanded.Event.ErrorEventHandler.handle/2"
    end

    test "should include the stack trace in failure context", %{handler: handler, ref: ref} do
      send_exception_event(handler)

      assert_receive {:exception, :stopping, error, %FailureContext{stacktrace: stacktrace}}
      assert_receive {:DOWN, ^ref, :process, ^handler, %RuntimeError{message: "exception"}}

      assert error == %RuntimeError{message: "exception"}
      refute is_nil(stacktrace)
    end
  end

  describe "event handler `error/3` callback function" do
    test "should call on error", %{handler: handler, ref: ref} do
      send_error_event(handler)

      assert_receive {:error, :stopping}
      assert_receive {:DOWN, ^ref, :process, ^handler, :failed}
    end

    test "should call on exception", %{handler: handler, ref: ref} do
      send_exception_event(handler)

      assert_receive {:exception, :stopping, _error, _failure_context}
      assert_receive {:DOWN, ^ref, :process, ^handler, %RuntimeError{message: "exception"}}
    end
  end

  test "should stop event handler on error by default", %{handler: handler, ref: ref} do
    send_error_event(handler)

    assert_receive {:error, :stopping}
    assert_receive {:DOWN, ^ref, :process, ^handler, :failed}
    refute Process.alive?(handler)
  end

  test "should stop event handler when invalid error response returned", %{
    handler: handler,
    ref: ref
  } do
    send_error_event(handler, strategy: "invalid")

    assert_receive {:error, :invalid}

    assert_receive {:DOWN, ^ref, :process, ^handler, :failed}
    refute Process.alive?(handler)
  end

  test "should retry event handler on error", %{handler: handler, ref: ref} do
    send_error_event(handler, strategy: "retry")

    assert_receive {:error, :failed, %{failures: 1}}
    assert_receive {:error, :failed, %{failures: 2}}
    assert_receive {:error, :too_many_failures, %{failures: 3}}

    assert_receive {:DOWN, ^ref, :process, ^handler, :too_many_failures}
    refute Process.alive?(handler)
  end

  test "should retry event handler after delay on error", %{
    handler: handler,
    ref: ref
  } do
    send_error_event(handler, strategy: "retry", delay: 10)

    assert_receive {:error, :failed, %{failures: 1, delay: 10}}
    assert_receive {:error, :failed, %{failures: 2, delay: 10}}
    assert_receive {:error, :too_many_failures, %{failures: 3, delay: 10}}

    assert_receive {:DOWN, ^ref, :process, ^handler, :too_many_failures}
    refute Process.alive?(handler)
  end

  test "should skip event on error", %{handler: handler, ref: ref} do
    send_error_event(handler, strategy: "skip")

    assert_receive {:error, :skipping}

    # Event handler should still be alive
    refute_receive {:DOWN, ^ref, :process, ^handler, :too_many_failures}
    assert Process.alive?(handler)

    # Should ack errored event
    assert GenServer.call(handler, :last_seen_event) == 1
  end

  defp send_error_event(handler, opts \\ []) do
    send_events_to_handler(handler, [
      %ErrorEvent{
        reply_to: reply_to(),
        strategy: Keyword.get(opts, :strategy, "default"),
        delay: Keyword.get(opts, :delay)
      }
    ])
  end

  defp send_exception_event(handler) do
    send_events_to_handler(handler, [
      %ExceptionEvent{reply_to: reply_to()}
    ])
  end

  defp send_events_to_handler(handler, events) do
    recorded_events = EventFactory.map_to_recorded_events(events)

    send(handler, {:events, recorded_events})
  end

  defp reply_to, do: :erlang.pid_to_list(self())
end
