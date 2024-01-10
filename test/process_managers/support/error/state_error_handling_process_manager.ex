defmodule Commanded.ProcessManagers.StateErrorHandlingProcessManager do
  @moduledoc false

  alias Commanded.ProcessManagers.ErrorAggregate.Commands.AttemptProcess
  alias Commanded.ProcessManagers.ErrorAggregate.Events.ProcessStarted
  alias Commanded.ProcessManagers.{ErrorApp, FailureContext}
  alias Commanded.ProcessManagers.StateErrorHandlingProcessManager

  use Commanded.ProcessManagers.ProcessManager,
    application: ErrorApp,
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

  def error({:error, error}, event, %FailureContext{} = failure_context) do
    %FailureContext{process_manager_state: %{reply_to: reply_to}} = failure_context

    pid = :erlang.list_to_pid(reply_to)

    send(pid, {:error, error, event, failure_context})

    {:stop, :stopping}
  end
end
