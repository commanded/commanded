defmodule Commanded.Event.Upcast.BatchEventHandler do
  use Commanded.Event.Handler,
    application: Commanded.DefaultApp,
    name: __MODULE__,
    batch_size: 5

  alias Commanded.Event.Upcast.Events.{EventFive, EventFour, EventOne, EventThree, EventTwo}

  def handle_batch([{_first, _metadata} | _rest] = events), do: send_reply(events)

  defp send_reply([{%{reply_to: reply_to}, _metadata} | _rest] = events) do
    send(:erlang.list_to_pid(reply_to), events)
    :ok
  end
end
