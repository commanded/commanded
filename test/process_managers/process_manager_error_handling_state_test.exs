defmodule Commanded.ProcessManager.ProcessManagerErrorHandlingStateTest do
  use Commanded.StorageCase

  alias Commanded.ProcessManagers.{
    StateErrorHandlingProcessManager,
    ErrorRouter,
  }
  alias Commanded.ProcessManagers.ErrorAggregate.Commands.StartProcess

  test "should receive the aggregate state in the context" do
    process_uuid = UUID.uuid4()
    command = %StartProcess{
      process_uuid: process_uuid,
      reply_to: reply_to(),
    }

    {:ok, _process_router} = StateErrorHandlingProcessManager.start_link()

    assert :ok = ErrorRouter.dispatch(command)

    assert_receive :got_from_context
  end

  defp reply_to, do: self() |> :erlang.pid_to_list()
end
