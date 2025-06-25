defmodule Commanded.Event.ErrorHandlingBatchHandler do
  use Commanded.Event.Handler,
    application: Commanded.DefaultApp,
    name: __MODULE__,
    batch_size: 5

  alias Commanded.Event.ErrorAggregate.Events.ErrorEvent
  alias Commanded.Event.FailureContext
  alias Commanded.Event.ReplyEvent

  require Logger

  @impl true
  def handle_batch([{%ErrorEvent{strategy: "retry"}, _metadata} | _rest]) do
    {:error, :bad_value}
  end

  def handle_batch([{%ErrorEvent{strategy: "skip"}, _metadata} | _rest]) do
    {:error, :skipping}
  end

  def handle_batch([{%ReplyEvent{value: :raise}, _metadata} | _rest]) do
    raise ArgumentError, "Raise"
  end

  def handle_batch([{%ReplyEvent{reply_to: reply_to, value: value}, _metadata} | _rest])
      when value != :error do
    send(reply_to, {:batch, self(), value})

    :ok
  end

  def handle_batch([{_event, _metadata} | _rest]) do
    Logger.info("Returning bad value error")
    {:error, :bad_value}
  end

  def handle_batch(events) do
    Logger.error("Unexpected fall-through with #{inspect(events)}")
    raise ArgumentError, "Bad events"
  end

  @impl true
  def error({:error, :skipping}, [%ErrorEvent{reply_to: reply_to} | _], _failure_context) do
    send(reply_to, {:error, :skipping})

    :skip
  end

  def error(
        {:error, reason},
        [%ErrorEvent{strategy: "default", reply_to: reply_to} | _],
        _failure_context
      ) do
    send(reply_to, {:error, :stopping})
    {:stop, reason}
  end

  def error(
        {:error, _reason},
        [%ErrorEvent{strategy: "retry", reply_to: reply_to} | _],
        failure_context
      ) do
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

  def error(
        {:error, %ArgumentError{message: "Raise"} = reason},
        [%Commanded.Event.ReplyEvent{reply_to: reply_to, value: :raise} | _],
        _failure_context
      ) do
    send(reply_to, {:error, :stopping})
    {:stop, reason}
  end
end
