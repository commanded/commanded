defmodule Commanded.Event.GracefulShutdownHandler do
  use Commanded.Event.Handler,
    application: Commanded.DefaultApp,
    name: __MODULE__

  def handle(%{sleep_for: milliseconds} = event, metadata) do
    %{reply_to: reply_to} = event

    Process.sleep(milliseconds)

    send(reply_to, {:event, event, metadata})

    :ok
  end
end
