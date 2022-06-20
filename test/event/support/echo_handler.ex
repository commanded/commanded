defmodule Commanded.Event.EchoHandler do
  use Commanded.Event.Handler,
    application: Commanded.MockedApp,
    name: __MODULE__

  alias Commanded.Event.ReplyEvent

  @impl Commanded.Event.Handler
  def handle(%ReplyEvent{} = event, metadata) do
    %ReplyEvent{reply_to: reply_to} = event

    reply_to = :erlang.list_to_pid(reply_to)

    send(reply_to, {:event, self(), event, metadata})

    :ok
  end
end
