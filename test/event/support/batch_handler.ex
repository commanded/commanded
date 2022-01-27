defmodule Commanded.Event.BatchHandler do
  use Commanded.Event.Handler,
    application: Commanded.DefaultApp,
    name: __MODULE__,
    batch_size: 5

  alias Commanded.Event.ReplyEvent

  @impl Commanded.Event.Handler
  def handle_batch([first | _reset] = events, metadata) do
    %ReplyEvent{reply_to: reply_to} = first

    send(reply_to, {:batch, self(), events, metadata})

    :ok
  end
end
