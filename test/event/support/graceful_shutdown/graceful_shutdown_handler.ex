defmodule Commanded.Event.GracefulShutdownHandler do
  use Commanded.Event.Handler,
    application: Commanded.MockedApp,
    name: __MODULE__

  def handle(event, metadata) do
    %{reply_to: reply_to} = event

    send(reply_to, {:event, event, metadata})

    receive do
      :continue ->
        send(reply_to, {:continue, event, metadata})

        :ok
    end

    :ok
  end
end
