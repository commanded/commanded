defmodule Commanded.ProcessManagers.ErrorHandlingProcessManager do
  @moduledoc false

  alias Commanded.ProcessManagers.{
    ErrorHandlingProcessManager,
    ErrorRouter,
  }
  alias Commanded.ProcessManagers.ErrorAggregate.Commands.{
    AttemptProcess,
    ContinueProcess,
  }
  alias Commanded.ProcessManagers.ErrorAggregate.Events.{
    ProcessContinued,
    ProcessStarted,
  }

  use Commanded.ProcessManagers.ProcessManager,
    name: "ErrorHandlingProcessManager",
    router: ErrorRouter

  defstruct [:process_uuid]

  def interested?(%ProcessStarted{process_uuid: process_uuid}), do: {:start, process_uuid}
  def interested?(%ProcessContinued{process_uuid: process_uuid}), do: {:continue, process_uuid}

  def handle(
    %ErrorHandlingProcessManager{},
    %ProcessStarted{process_uuid: process_uuid, strategy: strategy, delay: delay})
  do
    %AttemptProcess{process_uuid: process_uuid, strategy: strategy, delay: delay}
  end

  def handle(%ErrorHandlingProcessManager{}, %ProcessContinued{}) do
    reply(:process_continued)
    []
  end

  # stop after three attempts
  def error({:error, :failed}, %AttemptProcess{strategy: "retry"}, _pending_commands, %{attempts: attempts} = context)
    when attempts >= 2
  do
    reply({:error, :too_many_attempts, record_attempt(context)})

    {:stop, :too_many_attempts}
  end

  # retry command with delay
  def error({:error, :failed}, %AttemptProcess{strategy: "retry", delay: delay}, _pending_commands, context)
    when is_integer(delay)
  do
    context = record_attempt(context)
    reply_failure(Map.put(context, :delay, delay))

    {:retry, delay, context}
  end

  # retry command
  def error({:error, :failed}, %AttemptProcess{strategy: "retry"}, _pending_commands, context) do
    context = record_attempt(context)
    reply_failure(context)

    {:retry, context}
  end

  # skip failed command, continue pending
  def error({:error, :failed}, %AttemptProcess{strategy: "skip"}, _pending_commands, context) do
    reply({:error, :failed, record_attempt(context)})

    {:skip, :continue_pending}
  end

  # continue with modified command
  def error({:error, :failed}, %AttemptProcess{strategy: "continue", process_uuid: process_uuid}, pending_commands, context) do
    context = record_attempt(context)
    reply({:error, :failed, context})

    continue = %ContinueProcess{process_uuid: process_uuid}

    {:continue, [continue | pending_commands], context}
  end

  defp record_attempt(context) do
    Map.update(context, :attempts, 1, fn attempts -> attempts + 1 end)
  end

  defp reply_failure(context) do
    reply({:error, :failed, context})
  end

  defp reply(message) do
    reply_to = Agent.get({:global, ErrorHandlingProcessManager}, fn reply_to -> reply_to end)

    send(reply_to, message)
  end
end
