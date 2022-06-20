defmodule Commanded.Event.StatefulEventHandler do
  use Commanded.Event.Handler,
    application: Commanded.MockedApp,
    name: __MODULE__

  def init(config) do
    config = Keyword.put_new(config, :state, 0)

    {:ok, config}
  end

  def handle(%{update_state?: true} = event, metadata) do
    %{reply_to: reply_to} = event
    %{state: state} = metadata

    reply_to = :erlang.list_to_pid(reply_to)

    send(reply_to, {:event, event, metadata})

    {:ok, state + 1}
  end

  def handle(%{update_state?: false} = event, metadata) do
    %{reply_to: reply_to} = event

    reply_to = :erlang.list_to_pid(reply_to)

    send(reply_to, {:event, event, metadata})

    :ok
  end
end
