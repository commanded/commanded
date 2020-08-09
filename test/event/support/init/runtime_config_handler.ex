defmodule Commanded.Event.RuntimeConfigHandler do
  use Commanded.Event.Handler

  alias Commanded.DefaultApp

  def init(config) do
    {reply_to, config} = Keyword.pop!(config, :reply_to)
    {tenant, config} = Keyword.pop!(config, :tenant)

    config =
      config
      |> Keyword.put(:application, Module.concat([DefaultApp, tenant]))
      |> Keyword.put(:name, inspect(__MODULE__) <> ".#{tenant}")

    send(reply_to, {:init, tenant})

    {:ok, config}
  end
end
