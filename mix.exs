defmodule Commanded.Mixfile do
  use Mix.Project

  @version "1.4.2"

  def project do
    [
      app: :commanded,
      version: @version,
      elixir: "~> 1.10",
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      description: description(),
      docs: docs(),
      package: package(),
      aliases: aliases(),
      build_embedded: Mix.env() == :prod,
      start_permanent: Mix.env() == :prod,
      consolidate_protocols: Mix.env() == :prod,
      dialyzer: dialyzer(),
      name: "Commanded",
      source_url: "https://github.com/commanded/commanded"
    ]
  end

  def application do
    [
      extra_applications: extra_applications(Mix.env()),
      mod: {Commanded, []}
    ]
  end

  defp extra_applications(:test), do: [:crypto, :logger, :phoenix_pubsub]
  defp extra_applications(_env), do: [:crypto, :logger]

  defp elixirc_paths(env) when env in [:bench, :test],
    do: [
      "lib",
      "test/aggregates/support",
      "test/application/support",
      "test/commands/support",
      "test/event/support",
      "test/event_store/support",
      "test/example_domain",
      "test/middleware/support",
      "test/helpers",
      "test/process_managers/support",
      "test/pubsub/support",
      "test/registration/support",
      "test/subscriptions/support",
      "test/support"
    ]

  defp elixirc_paths(_env), do: ["lib", "test/helpers"]

  defp deps do
    [
      {:backoff, "~> 1.1"},

      # Telemetry
      {:telemetry, "~> 0.4 or ~> 1.0"},
      {:telemetry_registry, "~> 0.2 or ~> 0.3"},

      # Optional dependencies
      {:jason, "~> 1.4", optional: true},
      {:phoenix_pubsub, "~> 2.1", optional: true},

      # Build and test tools
      {:benchfella, "~> 0.3", only: :bench},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.3", only: [:dev, :test], runtime: false},
      {:ex_doc, ">= 0.0.0", only: :dev},
      {:local_cluster, "~> 1.2", only: :test, runtime: false},
      {:mix_test_watch, "~> 1.1", only: :dev},
      {:mox, "~> 1.0", only: [:bench, :test]}
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
      skip_undefined_reference_warnings_on: ["CHANGELOG.md"],
      extras: [
        "CHANGELOG.md",
        "guides/Getting Started.md",
        "guides/Choosing an Event Store.md",
        "guides/Usage.md",
        "guides/Application.md",
        "guides/Aggregates.md",
        "guides/Commands.md",
        "guides/Events.md",
        "guides/Process Managers.md",
        "guides/Supervision.md",
        "guides/Serialization.md",
        "guides/Read Model Projections.md",
        "guides/Testing.md",
        "guides/Deployment.md",
        "guides/upgrades/0.19-1.0.md": [
          filename: "0.19-1.0",
          title: "Upgrade guide v0.19.x to v1.0"
        ]
      ],
      groups_for_extras: [
        Introduction: [
          "guides/Getting Started.md",
          "guides/Choosing an Event Store.md",
          "guides/Usage.md"
        ],
        "Building blocks": [
          "guides/Application.md",
          "guides/Aggregates.md",
          "guides/Commands.md",
          "guides/Events.md",
          "guides/Process Managers.md"
        ],
        Other: [
          "guides/Supervision.md",
          "guides/Serialization.md",
          "guides/Read Model Projections.md",
          "guides/Testing.md",
          "guides/Deployment.md"
        ],
        Upgrades: [
          "guides/upgrades/0.19-1.0.md"
        ]
      ],
      groups_for_modules: [
        Aggregates: [
          Commanded.Aggregate.Multi,
          Commanded.Aggregates.Aggregate,
          Commanded.Aggregates.AggregateStateBuilder,
          Commanded.Aggregates.AggregateLifespan,
          Commanded.Aggregates.DefaultLifespan,
          Commanded.Aggregates.ExecutionContext,
          Commanded.Aggregates.Supervisor
        ],
        Commands: [
          Commanded.Commands.CompositeRouter,
          Commanded.Commands.ExecutionResult,
          Commanded.Commands.Handler,
          Commanded.Commands.Router
        ],
        Events: [
          Commanded.Event.FailureContext,
          Commanded.Event.Handler,
          Commanded.Event.Mapper,
          Commanded.Event.Upcaster
        ],
        "Process Managers": [
          Commanded.ProcessManagers.FailureContext,
          Commanded.ProcessManagers.ProcessManager
        ],
        "Event Store": [
          Commanded.EventStore,
          Commanded.EventStore.Adapter,
          Commanded.EventStore.Adapters.InMemory,
          Commanded.EventStore.EventData,
          Commanded.EventStore.RecordedEvent,
          Commanded.EventStore.SnapshotData,
          Commanded.EventStore.TypeProvider
        ],
        "Pub Sub": [
          Commanded.PubSub,
          Commanded.PubSub.Adapter,
          Commanded.PubSub.LocalPubSub,
          Commanded.PubSub.PhoenixPubSub
        ],
        Registry: [
          Commanded.Registration,
          Commanded.Registration.Adapter,
          Commanded.Registration.LocalRegistry,
          Commanded.Registration.GlobalRegistry
        ],
        Serialization: [
          Commanded.Serialization.JsonDecoder,
          Commanded.Serialization.JsonSerializer,
          Commanded.Serialization.ModuleNameTypeProvider
        ],
        Tasks: [
          Mix.Tasks.Commanded.Reset
        ],
        Middleware: [
          Commanded.Middleware,
          Commanded.Middleware.ConsistencyGuarantee,
          Commanded.Middleware.ExtractAggregateIdentity,
          Commanded.Middleware.Logger,
          Commanded.Middleware.Pipeline
        ],
        Testing: [
          Commanded.AggregateCase,
          Commanded.Assertions.EventAssertions
        ]
      ],
      nest_modules_by_prefix: [
        Commanded.Aggregate,
        Commanded.Aggregates,
        Commanded.Commands,
        Commanded.Event,
        Commanded.ProcessManagers,
        Commanded.EventStore,
        Commanded.PubSub,
        Commanded.Registration,
        Commanded.Serialization,
        Commanded.Middleware
      ]
    ]
  end

  defp package do
    [
      files: [
        "lib",
        "mix.exs",
        ".formatter.exs",
        "README*",
        "LICENSE*",
        "CHANGELOG*",
        "test/event_store/support",
        "test/example_domain",
        "test/helpers",
        "test/registration/support",
        "test/support"
      ],
      maintainers: ["Ben Smith"],
      licenses: ["MIT"],
      links: %{
        "GitHub" => "https://github.com/commanded/commanded",
        "Docs" => "https://hexdocs.pm/commanded/",
        "Sponsor" => "https://opencollective.com/commanded"
      }
    ]
  end

  defp aliases do
    []
  end

  defp dialyzer do
    [
      ignore_warnings: ".dialyzer_ignore.exs",
      plt_add_apps: [:ex_unit, :jason, :mix, :phoenix_pubsub],
      plt_add_deps: :app_tree,
      plt_file: {:no_warn, "priv/plts/commanded.plt"}
    ]
  end
end
