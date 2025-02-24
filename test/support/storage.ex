defmodule Commanded.EventStore.Adapters.EventStore.Storage do
  alias EventStore.Config
  alias EventStore.Storage.Initializer

  def connect(config) do
    postgrex_config = Config.default_postgrex_opts(config)

    Postgrex.start_link(postgrex_config)
  end

  def config(schema \\ "public") do
    TestEventStore
    |> Config.parsed(:commanded)
    |> Keyword.put(:schema, schema)
  end

  def reset!(conn, config), do: Initializer.reset!(conn, config)
end
