defmodule Commanded.Event.ErrorEventHandler do
  @moduledoc false

  use Commanded.Event.Handler,
    application: Commanded.DefaultApp,
    name: __MODULE__

  alias Commanded.Event.FailureContext
  alias Commanded.Event.ErrorAggregate.Events.{ErrorEvent, ExceptionEvent}

  # Simulate event handling error reply
  def handle(%ErrorEvent{}, _metadata) do
    {:error, :failed}
  end

  # Simulate event handling exception
  def handle(%ExceptionEvent{}, _metadata) do
    raise "exception"
  end

  # Default behaviour is to stop the event handler with the given error reason
  def error({:error, reason}, %ErrorEvent{strategy: "default"} = event, _failure_context) do
    %ErrorEvent{reply_to: reply_to} = event

    send_reply(reply_to, {:error, :stopping})

    {:stop, reason}
  end

  def error({:error, :failed}, %ErrorEvent{strategy: "retry"} = event, failure_context) do
    %ErrorEvent{delay: delay, reply_to: reply_to} = event
    %FailureContext{context: context} = failure_context

    context = context |> record_failure() |> Map.put(:delay, delay)

    case Map.get(context, :failures) do
      too_many when too_many >= 3 ->
        # stop error handler after third failure
        send_reply(reply_to, {:error, :too_many_failures, context})

        {:stop, :too_many_failures}

      _ ->
        # retry event, record failure count in context map
        send_reply(reply_to, {:error, :failed, context})

        {:retry, context}
    end
  end

  # Skip event
  def error({:error, :failed}, %ErrorEvent{strategy: "skip"} = event, _failure_context) do
    %ErrorEvent{reply_to: reply_to} = event

    send_reply(reply_to, {:error, :skipping})

    :skip
  end

  # Return an invalid response
  def error({:error, :failed}, %ErrorEvent{strategy: "invalid"} = event, _failure_context) do
    %ErrorEvent{reply_to: reply_to} = event

    send_reply(reply_to, {:error, :invalid})

    :invalid
  end

  def error({:error, error}, %ExceptionEvent{} = event, failure_context) do
    %ExceptionEvent{reply_to: reply_to} = event

    send_reply(reply_to, {:exception, :stopping, error, failure_context})

    {:stop, error}
  end

  defp record_failure(context) do
    Map.update(context, :failures, 1, fn failures -> failures + 1 end)
  end

  defp send_reply(reply_to, reply) do
    pid = :erlang.list_to_pid(reply_to)

    send(pid, reply)
  end
end
