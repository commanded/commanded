defmodule Commanded.Mixfile do
  use Mix.Project

  def project do
    [
      app: :commanded,
      version: "0.8.4",
      elixir: "~> 1.3",
      elixirc_paths: elixirc_paths(Mix.env),
      description: description,
      package: package,
      build_embedded: Mix.env == :prod,
      start_permanent: Mix.env == :prod,
      consolidate_protocols: Mix.env == :prod,
      deps: deps
    ]
  end

  def application do
    [
      applications: [
        :logger,
        :poison,
        :uuid,
      ],
      mod: {Commanded.Application, []}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/example_domain", "test/helpers"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:eventstore, "~> 0.7", optional: true, only: :test},
      {:ex_doc, "~> 0.14", only: :dev},
      {:markdown, github: "devinus/markdown", only: :dev},
      {:mix_test_watch, "~> 0.2", only: :dev},
      {:poison, "~> 2.2"},
      {:uuid, "~> 1.1"},
      {:extreme, "~> 0.7", optional: true, only: :test},
      {:hackney, "~> 1.6.0", override: true},
      {:docker, github: "bearice/elixir-docker", only: :test},
      {:httpoison, "~> 0.8.0", only: :test},
    ]
  end

  defp description do
"""
Command handling middleware for CQRS applications
"""
  end

  defp package do
    [
      files: ["lib", "mix.exs", "README*", "LICENSE*"],
      maintainers: ["Ben Smith"],
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/slashdotdash/commanded",
               "Docs" => "https://hexdocs.pm/commanded/"}
    ]
  end
end
