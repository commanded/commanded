defmodule EventStore.Mixfile do
  use Mix.Project

  def project do
    [app: :eventstore,
     version: "0.0.1",
     elixir: "~> 1.2",
     description: description,
     package: package,
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     deps: deps]
  end

  # Configuration for the OTP application
  #
  # Type "mix help compile.app" for more information
  def application do
    [applications: [
      :logger,
      :postgrex
      ]
    ]
  end

  # Dependencies can be Hex packages:
  #
  #   {:mydep, "~> 0.3.0"}
  #
  # Or git/path repositories:
  #
  #   {:mydep, git: "https://github.com/elixir-lang/mydep.git", tag: "0.1.0"}
  #
  # Type "mix help deps" for more examples and options
  defp deps do
    [
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
end
