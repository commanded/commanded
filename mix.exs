defmodule EventStore.Mixfile do
  use Mix.Project

  def project do
    [
      app: :eventstore,
      version: "0.9.0",
      elixir: "~> 1.5",
      elixirc_paths: elixirc_paths(Mix.env),
      description: description(),
      package: package(),
      build_embedded: Mix.env == :prod,
      start_permanent: Mix.env == :prod,
      consolidate_protocols: Mix.env == :prod,
      aliases: aliases(),
      deps: deps(),
      dialyzer: [plt_add_deps: :project]
    ]
  end

  def application do
    [
      extra_applications: [
        :logger,
        :poolboy,
      ],
      mod: {EventStore.Application, []}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(:bench), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:benchfella, "~> 0.3", only: :bench},
      {:credo, "~> 0.7", only: [:dev, :test]},
      {:dialyxir, "~> 0.4", only: :dev},
      {:ex_doc, "~> 0.16", only: :dev},
      {:fsm, "~> 0.3"},
      {:markdown, github: "devinus/markdown", only: :dev},
      {:mix_test_watch, "~> 0.4", only: :dev},
      {:poison, "~> 3.0", only: [:bench, :test]},
      {:poolboy, "~> 1.5"},
      {:postgrex, "~> 0.13"},
      {:uuid, "~> 1.1", only: [:bench, :test]},
    ]
  end

  defp description do
"""
EventStore using PostgreSQL for persistence.
"""
  end

  defp package do
    [
      files: ["lib", "mix.exs", "README*", "LICENSE*"],
      maintainers: ["Ben Smith"],
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/slashdotdash/eventstore",
               "Docs" => "https://hexdocs.pm/eventstore/"}
    ]
  end

  defp aliases do
    [
      "es.setup": ["event_store.create"],
      "es.reset": ["event_store.drop", "event_store.create"],
      "benchmark": ["es.reset", "app.start", "bench"],
    ]
  end
end
