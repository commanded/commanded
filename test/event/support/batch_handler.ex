defmodule Commanded.Event.BatchHandler do
  use Commanded.Event.Handler,
    application: Commanded.DefaultApp,
    name: __MODULE__,
    batch_size: 5

  alias Commanded.Event.ReplyEvent
  require Logger

  @impl true
  def handle_batch([{%ReplyEvent{value: :error}, _metadata} | _rest]) do
    Logger.info("Handle batch with error")
    {:error, :bad_value}
  end

  def handle_batch([{first, metadata} | _rest] = events) do
    maybe_error_event = Enum.find(events, fn {%ReplyEvent{value: value}, _metadata} -> value == :error end)
    case maybe_error_event do
      nil ->
        Logger.info("Handle regular batch")
        %ReplyEvent{reply_to: reply_to} = first

        send(reply_to, {:batch, self(), events, metadata})

        :ok
      {event, _metadata} ->
        Logger.info("Handle specific bad event")
        {:error, :bad_value, event}
    end
  end

  def handle_batch(events) do
    Logger.error("Unexpected fall-through with #{inspect events}")
    raise ArgumentError, "Bad events"
  end
 end
