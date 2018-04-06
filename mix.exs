defmodule Commanded.Mixfile do
  use Mix.Project

  @version "0.16.0"

  def project do
    [
      app: :commanded,
      version: @version,
      elixir: "~> 1.5",
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      description: description(),
      docs: docs(),
      package: package(),
      build_embedded: Mix.env() == :prod,
      start_permanent: Mix.env() == :prod,
      consolidate_protocols: Mix.env() == :prod,
      name: "Commanded",
      source_url: "https://github.com/commanded/commanded"
    ]
  end

  def application do
    [
      extra_applications: [
        :logger
      ],
      mod: {Commanded.Application, []}
    ]
  end

  defp elixirc_paths(:test),
    do: [
      "lib",
      "test/aggregates/support",
      "test/commands/support",
      "test/event/support",
      "test/example_domain",
      "test/helpers",
      "test/process_managers/support",
      "test/registration/support",
      "test/support"
    ]

  defp elixirc_paths(_), do: ["lib", "test/helpers"]

  defp deps do
    [
      {:poison, "~> 3.1"},
      {:uuid, "~> 1.1"},

      # Build & test tools
      {:dialyxir, "~> 0.5", only: :dev, runtime: false},
      {:ex_doc, "~> 0.17", only: :dev},
      {:mix_test_watch, "~> 0.6", only: :dev},
      {:mox, "~> 0.3", only: :test},

      # Optional dependencies
      {:phoenix_pubsub, "~> 1.0", optional: true}
    ]
  end

  defp description do
    """
    Use Commanded to build your own Elixir applications following the CQRS/ES pattern.
    """
  end

  defp docs do
    [
      main: "Commanded",
      canonical: "http://hexdocs.pm/commanded",
      source_ref: "v#{@version}",
      extra_section: "GUIDES",
      extras: [
        "guides/Getting Started.md",
        "guides/Choosing an Event Store.md",
        "guides/Usage.md",
        "guides/Aggregates.md",
        "guides/Commands.md",
        "guides/Events.md",
        "guides/Process Managers.md",
        "guides/Supervision.md",
        "guides/Serialization.md",
        "guides/Read Model Projections.md",
        "guides/Testing.md",
        "guides/Deployment.md",
        "CHANGELOG.md"
      ]
    ]
  end

  defp package do
    [
      files: [
        "lib",
        "mix.exs",
        "README*",
        "LICENSE*",
        "CHANGELOG*",
        "test/event_store_adapter",
        "test/example_domain",
        "test/helpers",
        "test/registration"
      ],
      maintainers: ["Ben Smith"],
      licenses: ["MIT"],
      links: %{
        "GitHub" => "https://github.com/commanded/commanded",
        "Docs" => "https://hexdocs.pm/commanded/"
      }
    ]
  end
end
