defmodule Commanded.Event.Upcast.EventHandler do
  use Commanded.Event.Handler,
    application: Commanded.DefaultApp,
    name: __MODULE__

  alias Commanded.Event.Upcast.Events.{EventFive, EventFour, EventOne, EventThree, EventTwo}

  def handle(%EventOne{} = e, _), do: send_reply(e)
  def handle(%EventTwo{} = e, _), do: send_reply(e)
  def handle(%EventThree{} = e, _), do: send_reply(e)
  def handle(%EventFour{} = e, _), do: send_reply(e)
  def handle(%EventFive{} = e, _), do: send_reply(e)

  defp send_reply(%{reply_to: reply_to} = e) do
    send(:erlang.list_to_pid(reply_to), e)
    :ok
  end
end
