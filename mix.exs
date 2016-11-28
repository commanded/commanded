defmodule Commanded.Mixfile do
  use Mix.Project

  def project do
    [
      app: :commanded,
      version: "0.8.1",
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
        :eventstore,
        :poison,
        :uuid
      ],
      mod: {Commanded.Application, []}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/example_domain", "test/helpers"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:eventstore, "~> 0.6"},
      {:ex_doc, "~> 0.14", only: :dev},
      {:markdown, github: "devinus/markdown", only: :dev},
      {:mix_test_watch, "~> 0.2", only: :dev},
      {:poison, "~> 3.0"},
      {:uuid, "~> 1.1"},
      # devs
      {:dialyxir, "~> 0.3.5", only: :dev},   # simplify dialyzer, type: mix dialyzer.plt first
			{:mix_test_watch, "~> 0.2", only: :dev} # use mix test.watch for adicted TDD development
                                              # use mix test.watch blabla to point to your test file

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
