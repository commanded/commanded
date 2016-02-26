defmodule EventStore.Mixfile do
  use Mix.Project

  def project do
    [app: :eventstore,
     version: "0.0.4",
     elixir: "~> 1.2",
     description: description,
     package: package,
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     aliases: aliases,
     deps: deps]
  end

  def application do
    [applications: [
      :logger,
      :poison,
      :postgrex
      ]
    ]
  end

  defp deps do
    [
      {:ex_doc, "~> 0.11.4", only: :dev},
      {:markdown, github: "devinus/markdown", only: :dev},
      {:mix_test_watch, "~> 0.2", only: :dev},
      {:poison, "~> 2.1"},
      {:postgrex, "~> 0.11.1"},
      {:uuid, "~> 1.1"}
    ]
  end

  defp description do
"""
EventStore using Postgres for persistence.
"""
  end

  defp package do
    [
     files: ["lib", "priv", "mix.exs", "README*", "readme*", "LICENSE*", "license*"],
     maintainers: ["Ben Smith"],
     licenses: ["MIT"],
     links: %{"GitHub" => "https://github.com/slashdotdash/eventstore",
              "Docs" => "https://github.com/slashdotdash/eventstore"}
    ]
  end

  defp aliases do
    ["es.setup": ["event_store.create"],
     "es.reset": ["event_store.drop", "es.setup"]]
  end
end
