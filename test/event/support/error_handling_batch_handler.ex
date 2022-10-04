defmodule Commanded.Event.ErrorHandlingBatchHandler do
  use Commanded.Event.Handler,
    application: Commanded.DefaultApp,
    name: __MODULE__,
    batch_size: 5

  alias Commanded.Event.FailureContext
  alias Commanded.Event.ErrorAggregate.Events.ErrorEvent
  alias Commanded.Event.ReplyEvent

  require Logger

  @impl true
  def handle_batch([{%ErrorEvent{strategy: "retry"} = event, _metadata} | _rest]) do
    {:error, :bad_value, event}
  end

  def handle_batch([{%ErrorEvent{strategy: "skip"} = event, _metadata} | _rest]) do
    {:error, :skipping, event}
  end

  def handle_batch([{%ReplyEvent{reply_to: reply_to, value: value}, _metadata} | _rest]) when value != :error do
    send(reply_to, {:batch, self(), value})

    :ok
  end

  def handle_batch([{event, _metadata} | _rest]) do
    Logger.info("Returning bad value error")
    {:error, :bad_value, event}
  end

  def handle_batch(events) do
    Logger.error("Unexpected fall-through with #{inspect events}")
    raise ArgumentError, "Bad events"
  end

  @impl true
  def error({:error, :skipping}, %ErrorEvent{reply_to: reply_to}, _failure_context) do
    send(reply_to, {:error, :skipping})

    :skip
  end

  def error({:error, reason}, %ErrorEvent{strategy: "default"} = event, _failure_context) do
    %ErrorEvent{reply_to: reply_to} = event
    send(reply_to, {:error, :stopping})
    {:stop, reason}
  end

  def error({:error, _reason}, %ErrorEvent{strategy: "retry"} = event, failure_context) do
    %ErrorEvent{reply_to: reply_to} = event
    %FailureContext{context: context} = failure_context

    context = Map.update(context, :failures, 1, fn failures -> failures + 1 end)

    if Map.get(context, :failures) >= 3 do
      send(reply_to, {:error, :too_many_failures, context})
      {:stop, :too_many_failures}
    else
      send(reply_to, {:error, :retry, context})
      {:retry, context}
    end
  end
end
