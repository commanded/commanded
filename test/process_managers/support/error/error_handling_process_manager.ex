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
    %ProcessStarted{process_uuid: process_uuid, strategy: strategy, delay: delay, reply_to: reply_to})
  do
    %AttemptProcess{process_uuid: process_uuid, strategy: strategy, delay: delay, reply_to: reply_to}
  end

  def handle(%ErrorHandlingProcessManager{}, %ProcessContinued{reply_to: reply_to}) do
    send(reply_to, :process_continued)
    []
  end

  # stop after three attempts
  def error({:error, :failed}, %AttemptProcess{strategy: :retry, reply_to: reply_to}, _pending_commands, %{attempts: attempts} = context)
    when attempts >= 2
  do
    send(reply_to, {:error, :too_many_attempts, record_attempt(context)})

    {:stop, :too_many_attempts}
  end

  # retry command with delay
  def error({:error, :failed}, %AttemptProcess{strategy: :retry, delay: delay} = failed_command, _pending_commands, context)
    when is_integer(delay)
  do
    context = record_attempt(context)
    send_failure(failed_command, Map.put(context, :delay, delay))

    {:retry, delay, context}
  end

  # retry command
  def error({:error, :failed}, %AttemptProcess{strategy: :retry} = failed_command, _pending_commands, context) do
    context = record_attempt(context)
    send_failure(failed_command, context)

    {:retry, context}
  end

  # skip failed command, continue pending
  def error({:error, :failed}, %AttemptProcess{strategy: :skip, reply_to: reply_to}, _pending_commands, context) do
    send(reply_to, {:error, :failed, record_attempt(context)})

    {:skip, :continue_pending}
  end

  # continue with modified command
  def error({:error, :failed}, %AttemptProcess{strategy: :continue, process_uuid: process_uuid, reply_to: reply_to}, pending_commands, context) do
    context = record_attempt(context)
    send(reply_to, {:error, :failed, context})

    continue = %ContinueProcess{process_uuid: process_uuid, reply_to: reply_to}

    {:continue, [continue | pending_commands], context}
  end

  defp record_attempt(context) do
    Map.update(context, :attempts, 1, fn attempts -> attempts + 1 end)
  end

  defp send_failure(%AttemptProcess{reply_to: reply_to}, context) do
    send(reply_to, {:error, :failed, context})
  end
end
