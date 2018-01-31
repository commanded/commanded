defmodule Commanded.Event.ErrorEventHandler do
  @moduledoc false

  use Commanded.Event.Handler, name: __MODULE__

  alias Commanded.Event.ErrorAggregate.Events.ErrorEvent

  def handle(%ErrorEvent{}, _metadata) do
    # simulate event handling failure
    {:error, :failed}
  end

  # stop error handler after third failure
  def error({:error, :failed}, %ErrorEvent{strategy: "retry"} = event, %{failures: failures} = context)
    when failures >= 2
  do
    context = record_failure(context)

    send_reply({:error, :too_many_failures, context}, event)

    {:stop, :too_many_failures}
  end

  # retry event, record failure count in context map
  def error({:error, :failed}, %ErrorEvent{strategy: "retry"} = event, context) do
    context = record_failure(context)

    send_reply({:error, :failed, context}, event)

    {:retry, context}
  end

  # skip event
  def error({:error, :failed}, %ErrorEvent{strategy: "skip"} = event, _context) do
    send_reply({:error, :skipping}, event)

    :skip
  end

  # default behaviour is to stop the event handler with the given error reason
  def error({:error, reason}, %ErrorEvent{strategy: "default"} = event, _context) do
    send_reply({:error, :stopping}, event)

    {:stop, reason}
  end

  defp record_failure(context) do
    Map.update(context, :failures, 1, fn failures -> failures + 1 end)
  end

  defp send_reply(reply, %ErrorEvent{reply_to: reply_to}) do
    pid = :erlang.list_to_pid(reply_to)

    send(pid, reply)
  end
end
