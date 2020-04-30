defmodule Commanded.ProcessManager.ProcessManagerErrorHandlingStateTest do
  use ExUnit.Case

  alias Commanded.ProcessManagers.ErrorAggregate.Commands.StartProcess
  alias Commanded.ProcessManagers.ErrorRouter
  alias Commanded.ProcessManagers.ExampleApp
  alias Commanded.ProcessManagers.StateErrorHandlingProcessManager

  setup do
    start_supervised!(ExampleApp)
    start_supervised!(StateErrorHandlingProcessManager)

    :ok
  end

  test "should receive the aggregate state in the context" do
    command = %StartProcess{
      process_uuid: UUID.uuid4(),
      reply_to: reply_to()
    }

    assert :ok = ErrorRouter.dispatch(command, application: ExampleApp)

    assert_receive :got_from_context
  end

  defp reply_to, do: :erlang.pid_to_list(self())
end
