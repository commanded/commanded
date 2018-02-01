defmodule Commanded.Event.ErrorEventHandler do
  @moduledoc false

  use Commanded.Event.Handler, name: __MODULE__

  alias Commanded.Event.FailureContext
  alias Commanded.Event.ErrorAggregate.Events.ErrorEvent

  def handle(%ErrorEvent{}, _metadata) do
    # simulate event handling failure
    {:error, :failed}
  end

  def error({:error, :failed}, %ErrorEvent{strategy: "retry", delay: delay} = event, %FailureContext{
        context: context
      }) do
    context = context |> record_failure() |> Map.put(:delay, delay)

    case Map.get(context, :failures) do
      too_many when too_many >= 3 ->
        # stop error handler after third failure
        send_reply({:error, :too_many_failures, context}, event)

        {:stop, :too_many_failures}

      _ ->
        # retry event, record failure count in context map
        send_reply({:error, :failed, context}, event)

        {:retry, context}
    end
  end

  # skip event
  def error({:error, :failed}, %ErrorEvent{strategy: "skip"} = event, _failure_context) do
    send_reply({:error, :skipping}, event)

    :skip
  end

  # default behaviour is to stop the event handler with the given error reason
  def error({:error, reason}, %ErrorEvent{strategy: "default"} = event, _failure_context) do
    send_reply({:error, :stopping}, event)

    {:stop, reason}
  end

  # return an invalid response
  def error({:error, :failed}, %ErrorEvent{strategy: "invalid"} = event, _failure_context) do
    send_reply({:error, :invalid}, event)

    :invalid
  end

  defp record_failure(context) do
    Map.update(context, :failures, 1, fn failures -> failures + 1 end)
  end

  defp send_reply(reply, %ErrorEvent{reply_to: reply_to}) do
    pid = :erlang.list_to_pid(reply_to)

    send(pid, reply)
  end
end
