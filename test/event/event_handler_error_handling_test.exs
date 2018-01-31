defmodule Commanded.Event.EventHandlerErrorHandlingTest do
  use Commanded.StorageCase

  alias Commanded.Event.{ErrorEventHandler, ErrorRouter}
  alias Commanded.Event.ErrorAggregate.Commands.RaiseError
  
  test "should stop event handler on error by default" do
    uuid = UUID.uuid4()

    {:ok, handler} = ErrorEventHandler.start_link()

    Process.unlink(handler)
    ref = Process.monitor(handler)

    :ok = ErrorRouter.dispatch(%RaiseError{uuid: uuid, strategy: "default"})

    assert_receive {:DOWN, ^ref, _, _, _}
    refute Process.alive?(handler)
  end

  test "should retry event handler on error" do
    uuid = UUID.uuid4()

    {:ok, handler} = ErrorEventHandler.start_link()

    Process.unlink(handler)
    ref = Process.monitor(handler)

    :ok = ErrorRouter.dispatch(%RaiseError{uuid: uuid, strategy: "retry", reply_to: reply_to()})

    assert_receive {:error, :failed, %{failures: 1}}
    assert_receive {:error, :failed, %{failures: 2}}
    assert_receive {:error, :too_many_failures, %{failures: 3}}

    assert_receive {:DOWN, ^ref, _, _, :too_many_failures}
    refute Process.alive?(handler)
  end

  # skip event, check :last_seen_event

  defp reply_to, do: self() |> :erlang.pid_to_list()
end
