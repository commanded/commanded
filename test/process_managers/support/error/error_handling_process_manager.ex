defmodule Commanded.ProcessManagers.ErrorHandlingProcessManager do
  @moduledoc false

  alias Commanded.ProcessManagers.{ErrorHandlingProcessManager, FailureContext}

  alias Commanded.ProcessManagers.ErrorAggregate.Commands.{
    AttemptProcess,
    ContinueProcess,
    RaiseException
  }

  alias Commanded.ProcessManagers.ErrorApp

  alias Commanded.ProcessManagers.ErrorAggregate.Events.{
    ProcessContinued,
    ProcessDispatchException,
    ProcessError,
    ProcessException,
    ProcessStarted
  }

  use Commanded.ProcessManagers.ProcessManager,
    application: ErrorApp,
    name: "ErrorHandlingProcessManager"

  @derive Jason.Encoder
  defstruct [:process_uuid]

  def interested?(%ProcessStarted{process_uuid: process_uuid}), do: {:start, process_uuid}
  def interested?(%ProcessError{process_uuid: process_uuid}), do: {:start, process_uuid}
  def interested?(%ProcessException{process_uuid: process_uuid}), do: {:start, process_uuid}
  def interested?(%ProcessContinued{process_uuid: process_uuid}), do: {:continue, process_uuid}

  def interested?(%ProcessDispatchException{process_uuid: process_uuid}),
    do: {:start, process_uuid}

  def handle(%ErrorHandlingProcessManager{}, %ProcessStarted{} = event) do
    %ProcessStarted{
      process_uuid: process_uuid,
      reply_to: reply_to,
      strategy: strategy,
      delay: delay
    } = event

    %AttemptProcess{
      process_uuid: process_uuid,
      reply_to: reply_to,
      strategy: strategy,
      delay: delay
    }
  end

  def handle(%ErrorHandlingProcessManager{}, %ProcessDispatchException{} = event) do
    %ProcessDispatchException{process_uuid: process_uuid, reply_to: reply_to, message: message} =
      event

    %RaiseException{process_uuid: process_uuid, reply_to: reply_to, message: message}
  end

  # Simulate an error handling an event.
  def handle(%ErrorHandlingProcessManager{}, %ProcessError{} = event) do
    %ProcessError{message: message} = event

    {:error, message}
  end

  # Simulate an exception handling an event.
  def handle(%ErrorHandlingProcessManager{}, %ProcessException{} = event) do
    %ProcessException{message: message} = event

    raise message
  end

  def handle(%ErrorHandlingProcessManager{}, %ProcessContinued{} = event) do
    %ProcessContinued{reply_to: reply_to} = event

    reply(reply_to, :process_continued)

    []
  end

  # Skip events causing errors during event handling
  def error({:error, error}, %ProcessError{} = event, failure_context) do
    %ProcessError{reply_to: reply_to} = event

    reply(reply_to, {:error, error, failure_context})

    {:stop, error}
  end

  # Stop on exceptions during event handling
  def error({:error, error}, %ProcessException{} = event, failure_context) do
    %ProcessException{reply_to: reply_to} = event

    reply(reply_to, {:error, error, failure_context})

    {:stop, error}
  end

  # Stop on exceptions during command dispatch.
  def error({:error, error}, %RaiseException{} = command, failure_context) do
    %RaiseException{reply_to: reply_to} = command

    reply(reply_to, {:error, error, failure_context})

    {:stop, error}
  end

  # Stop after three attempts.
  def error(
        {:error, :failed},
        %AttemptProcess{strategy: "retry"} = command,
        %FailureContext{context: %{attempts: attempts}} = failure_context
      )
      when attempts >= 2 do
    %AttemptProcess{reply_to: reply_to} = command

    context = record_attempt(failure_context)
    reply(reply_to, {:error, :too_many_attempts, context, failure_context})

    {:stop, :too_many_attempts}
  end

  # Retry command with delay
  def error(
        {:error, :failed},
        %AttemptProcess{strategy: "retry", delay: delay} = command,
        failure_context
      )
      when is_integer(delay) do
    %AttemptProcess{reply_to: reply_to} = command

    context = failure_context |> record_attempt() |> Map.put(:delay, delay)
    reply(reply_to, {:error, :failed, context, failure_context})

    {:retry, delay, context}
  end

  # Retry command
  def error({:error, :failed}, %AttemptProcess{strategy: "retry"} = command, failure_context) do
    %AttemptProcess{reply_to: reply_to} = command

    context = record_attempt(failure_context)
    reply(reply_to, {:error, :failed, context, failure_context})

    {:retry, context}
  end

  # Skip failed command, continue pending
  def error({:error, :failed}, %AttemptProcess{strategy: "skip"} = command, failure_context) do
    %AttemptProcess{reply_to: reply_to} = command

    context = record_attempt(failure_context)
    reply(reply_to, {:error, :failed, context, failure_context})

    {:skip, :continue_pending}
  end

  # Continue with modified command
  def error({:error, :failed}, %AttemptProcess{strategy: "continue"} = command, failure_context) do
    %AttemptProcess{process_uuid: process_uuid, reply_to: reply_to} = command

    context = record_attempt(failure_context)
    reply(reply_to, {:error, :failed, context, failure_context})

    continue = %ContinueProcess{process_uuid: process_uuid, reply_to: reply_to}

    {:continue, [continue | failure_context.pending_commands], context}
  end

  defp record_attempt(%FailureContext{context: context}) do
    Map.update(context, :attempts, 1, fn attempts -> attempts + 1 end)
  end

  defp reply(reply_to, message) do
    pid = :erlang.list_to_pid(reply_to)

    send(pid, message)
  end
end
