defmodule Commanded.ReplyHandler do
  use Commanded.Event.Handler,
    application: Commanded.ExampleApplication,
    name: __MODULE__

  def handle(event, _metadata) do
    reply_to = Agent.get(:reply_to, fn reply_to -> reply_to end)

    send(reply_to, {:event, self(), event})

    :ok
  end
end
