defmodule EventStore.Mixfile do
  use Mix.Project

  @version "0.11.0"

  def project do
    [
      app: :eventstore,
      version: @version,
      elixir: "~> 1.4",
      elixirc_paths: elixirc_paths(Mix.env),
      deps: deps(),
      description: description(),
      package: package(),
      docs: docs(),
      build_embedded: Mix.env == :prod,
      start_permanent: Mix.env == :prod,
      consolidate_protocols: Mix.env == :prod,
      aliases: aliases(),
      preferred_cli_env: preferred_cli_env(),
      dialyzer: [plt_add_deps: :project],
      name: "EventStore",
      source_url: "https://github.com/slashdotdash/eventstore",
    ]
  end

  def application do
    [
      extra_applications: [
        :logger,
        :poolboy,
      ] ++ registry_applications(),
      mod: {EventStore.Application, []}
    ]
  end

  defp registry_applications do
    case Application.get_env(:eventstore, :registry) do
      :distributed -> [:swarm]
      _ -> []
    end
  end

  defp elixirc_paths(:bench),       do: ["lib", "test/support"]
  defp elixirc_paths(:distributed), do: ["lib", "test/support"]
  defp elixirc_paths(:local),       do: ["lib", "test/support"]
  defp elixirc_paths(:test),        do: ["lib", "test/support"]
  defp elixirc_paths(_),            do: ["lib"]

  defp deps do
    [
      {:benchfella, "~> 0.3", only: :bench},
      {:credo, "~> 0.7", only: [:dev, :test]},
      {:dialyxir, "~> 0.4", only: :dev},
      {:ex_doc, "~> 0.16", only: :dev},
      {:fsm, "~> 0.3"},
      {:markdown, github: "devinus/markdown", only: :dev},
      {:mix_test_watch, "~> 0.4", only: :dev},
      {:poison, "~> 3.0", optional: true},
      {:poolboy, "~> 1.5"},
      {:postgrex, "~> 0.13"},
      {:swarm, "~> 3.0", optional: true},
      {:uuid, "~> 1.1"},
    ]
  end

  defp description do
"""
EventStore using PostgreSQL for persistence.
"""
  end

  defp docs do
    [
      main: "EventStore",
      canonical: "http://hexdocs.pm/eventstore",
      source_ref: "v#{@version}",
      source_url: "https://github.com/slashdotdash/eventstore",
      extras: [
        "guides/Getting Started.md",
        "guides/Usage.md",
        "guides/Subscriptions.md",
        "guides/Cluster.md",
        "guides/Event Serialization.md",
        "guides/Upgrades.md",
      ],
    ]
  end

  defp package do
    [
      files: ["lib", "guides", "mix.exs", "README*", "LICENSE*"],
      maintainers: ["Ben Smith"],
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/slashdotdash/eventstore",
               "Docs" => "https://hexdocs.pm/eventstore/"}
    ]
  end

  defp aliases do
    [
      "es.setup":           ["event_store.create"],
      "es.reset":           ["event_store.drop", "event_store.create"],
      "event_store.reset":  ["event_store.drop", "event_store.create"],
      "benchmark":          ["es.reset", "app.start", "bench"],
      "test.all":           &test_registries/1,
      "test.distributed":   &test_distributed/1,
      "test.local":         &test_local/1,
    ]
  end

  defp preferred_cli_env do
    [
      "test.all":         :test,
      "test.distributed": :test,
      "test.local":       :test,
    ]
  end

  @registries [:local, :distributed]

  defp test_registries(args), do: Enum.map(@registries, &test_registry(&1, args))
  defp test_distributed(args), do: test_registry(:distributed, args)
  defp test_local(args), do: test_registry(:local, args)
  defp test_registry(registry, args) do
    test_args = if IO.ANSI.enabled?, do: ["--color"|args], else: ["--no-color"|args]

    IO.puts "==> Running tests for MIX_ENV=#{registry} mix test #{Enum.join(args, " ")}"

    {_, res} = System.cmd "mix", ["test"|test_args],
                          into: IO.binstream(:stdio, :line),
                          env: [{"MIX_ENV", to_string(registry)}]

    if res > 0 do
      System.at_exit(fn _ -> exit({:shutdown, 1}) end)
    end
  end
end
