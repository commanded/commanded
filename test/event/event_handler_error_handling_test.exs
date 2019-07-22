defmodule Commanded.Event.EventHandlerErrorHandlingTest do
  use Commanded.StorageCase

  alias Commanded.DefaultApp
  alias Commanded.Event.{ErrorEventHandler, ErrorRouter}
  alias Commanded.Event.ErrorAggregate.Commands.{RaiseError, RaiseException}

  setup do
    start_supervised!(DefaultApp)

    {:ok, handler} = ErrorEventHandler.start_link()

    Process.unlink(handler)

    [
      handler: handler,
      ref: Process.monitor(handler),
      uuid: UUID.uuid4()
    ]
  end

  describe "event handler `error/3` callback function" do
    test "should call on error", context do
      %{ref: ref, uuid: uuid} = context

      :ok =
        ErrorRouter.dispatch(%RaiseError{uuid: uuid, strategy: "default", reply_to: reply_to()})

      assert_receive {:error, :stopping}
      assert_receive {:DOWN, ^ref, _, _, :failed}
    end

    test "should call on exception", context do
      %{ref: ref, uuid: uuid} = context

      :ok =
        ErrorRouter.dispatch(%RaiseException{
          uuid: uuid,
          strategy: "default",
          reply_to: reply_to()
        })

      assert_receive {:exception, :stopping}
      assert_receive {:DOWN, ^ref, _, _, %RuntimeError{message: "exception"}}
    end
  end

  test "should stop event handler on error by default", context do
    %{handler: handler, ref: ref, uuid: uuid} = context

    :ok = ErrorRouter.dispatch(%RaiseError{uuid: uuid, strategy: "default", reply_to: reply_to()})

    assert_receive {:error, :stopping}

    assert_receive {:DOWN, ^ref, _, _, :failed}
    refute Process.alive?(handler)
  end

  test "should stop event handler when invalid error response returned", context do
    %{handler: handler, ref: ref, uuid: uuid} = context

    :ok = ErrorRouter.dispatch(%RaiseError{uuid: uuid, strategy: "invalid", reply_to: reply_to()})

    assert_receive {:error, :invalid}

    assert_receive {:DOWN, ^ref, _, _, :failed}
    refute Process.alive?(handler)
  end

  test "should retry event handler on error", context do
    %{handler: handler, ref: ref, uuid: uuid} = context

    :ok = ErrorRouter.dispatch(%RaiseError{uuid: uuid, strategy: "retry", reply_to: reply_to()})

    assert_receive {:error, :failed, %{failures: 1}}
    assert_receive {:error, :failed, %{failures: 2}}
    assert_receive {:error, :too_many_failures, %{failures: 3}}

    assert_receive {:DOWN, ^ref, _, _, :too_many_failures}
    refute Process.alive?(handler)
  end

  test "should retry event handler after delay on error", context do
    %{handler: handler, ref: ref, uuid: uuid} = context

    command = %RaiseError{uuid: uuid, strategy: "retry", delay: 10, reply_to: reply_to()}

    :ok = ErrorRouter.dispatch(command)

    assert_receive {:error, :failed, %{failures: 1, delay: 10}}
    assert_receive {:error, :failed, %{failures: 2, delay: 10}}
    assert_receive {:error, :too_many_failures, %{failures: 3, delay: 10}}

    assert_receive {:DOWN, ^ref, _, _, :too_many_failures}
    refute Process.alive?(handler)
  end

  test "should skip event on error", context do
    %{handler: handler, ref: ref, uuid: uuid} = context

    :ok = ErrorRouter.dispatch(%RaiseError{uuid: uuid, strategy: "skip", reply_to: reply_to()})

    assert_receive {:error, :skipping}

    # event handler should still be alive
    refute_receive {:DOWN, ^ref, _, _, :too_many_failures}
    assert Process.alive?(handler)

    # should ack bad event
    assert GenServer.call(handler, :last_seen_event) == 1
  end

  defp reply_to, do: self() |> :erlang.pid_to_list()
end
