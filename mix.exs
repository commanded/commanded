defmodule EventStore.Mixfile do
  use Mix.Project

  def project do
    [
      app: :eventstore,
      version: "0.2.1",
      elixir: "~> 1.2",
      description: description,
      package: package,
      build_embedded: Mix.env == :prod,
      start_permanent: Mix.env == :prod,
      aliases: aliases,
      deps: deps
    ]
  end

  def application do
    [
      applications: [
        :logger,
        :postgrex
      ],
      mod: {EventStore.Application, []}
    ]
  end

  defp deps do
    [
      {:benchfella, "~> 0.3.2", only: :bench},
      {:credo, "~> 0.3.7", only: [:dev, :test]},
      {:ex_doc, "~> 0.11.4", only: :dev},
      {:fsm, "~> 0.2.0"},
      {:markdown, github: "devinus/markdown", only: :dev},
      {:mix_test_watch, "~> 0.2.6", only: :dev},
      {:poolboy, "~> 1.5"},
      {:postgrex, "~> 0.11.1"},
      {:uuid, "~> 1.1", only: [:bench, :test]}
    ]
  end

  defp description do
"""
EventStore using PostgreSQL for persistence.
"""
  end

  defp package do
    [
      files: ["lib", "priv", "mix.exs", "README*", "readme*", "LICENSE*", "license*"],
      maintainers: ["Ben Smith"],
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/slashdotdash/eventstore",
               "Docs" => "https://hexdocs.pm/eventstore/"}
    ]
  end

  defp aliases do
    [
      "es.setup": ["event_store.create"],
      "es.reset": ["event_store.drop", "event_store.create"]
    ]
  end
end
