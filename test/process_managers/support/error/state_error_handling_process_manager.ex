defmodule Commanded.ProcessManagers.StateErrorHandlingProcessManager do
  @moduledoc false

  alias Commanded.ProcessManagers.{ExampleApp, StateErrorHandlingProcessManager}
  alias Commanded.ProcessManagers.ErrorAggregate.Commands.AttemptProcess
  alias Commanded.ProcessManagers.ErrorAggregate.Events.ProcessStarted

  use Commanded.ProcessManagers.ProcessManager,
    application: ExampleApp,
    name: "StateErrorHandlingProcessManager"

  defstruct [:process_uuid, :reply_to]

  def interested?(%ProcessStarted{process_uuid: process_uuid}), do: {:start, process_uuid}

  def handle(%StateErrorHandlingProcessManager{}, %ProcessStarted{process_uuid: process_uuid}) do
    %AttemptProcess{process_uuid: process_uuid}
  end

  def apply(%StateErrorHandlingProcessManager{}, %ProcessStarted{} = event) do
    %ProcessStarted{reply_to: reply_to, process_uuid: process_uuid} = event

    %StateErrorHandlingProcessManager{reply_to: reply_to, process_uuid: process_uuid}
  end

  def error(_, _, failure_context) do
    %{process_manager_state: %{reply_to: reply_to}} = failure_context

    send(:erlang.list_to_pid(reply_to), :got_from_context)

    {:stop, :stopping}
  end
end
