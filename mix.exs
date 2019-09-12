defmodule Commanded.Mixfile do
  use Mix.Project

  @version "0.19.1"

  def project do
    [
      app: :commanded,
      version: @version,
      elixir: "~> 1.6",
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      description: description(),
      docs: docs(),
      package: package(),
      aliases: aliases(),
      build_embedded: Mix.env() == :prod,
      start_permanent: Mix.env() == :prod,
      consolidate_protocols: Mix.env() == :prod,
      name: "Commanded",
      source_url: "https://github.com/commanded/commanded"
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {Commanded, []}
    ]
  end

  defp elixirc_paths(:test),
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
      "test/support"
    ]

  defp elixirc_paths(_env), do: ["lib", "test/helpers"]

  defp deps do
    [
      {:elixir_uuid, "~> 1.2"},

      # Build and test tools
      {:dialyxir, "~> 0.5", only: :dev, runtime: false},
      {:ex_doc, "~> 0.20", only: :dev},
      {:mix_test_watch, "~> 0.9", only: :dev},
      {:mox, "~> 0.5", only: :test},

      # Optional dependencies
      {:jason, "~> 1.1", optional: true},
      {:phoenix_pubsub, "~> 1.1", optional: true}
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
        "CHANGELOG.md",
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
        "guides/Deployment.md"
      ],
      groups_for_extras: [
        Introduction: [
          "guides/Getting Started.md",
          "guides/Choosing an Event Store.md",
          "guides/Usage.md"
        ],
        "Building blocks": [
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
        ]
      ],
      groups_for_modules: [
        Aggregates: [
          Commanded.Aggregate.Multi,
          Commanded.Aggregates.Aggregate,
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
          Commanded.EventStore.Adapters.InMemory,
          Commanded.EventStore.EventData,
          Commanded.EventStore.RecordedEvent,
          Commanded.EventStore.SnapshotData,
          Commanded.EventStore.TypeProvider
        ],
        "Pub Sub": [
          Commanded.PubSub,
          Commanded.PubSub.LocalPubSub,
          Commanded.PubSub.PhoenixPubSub
        ],
        Registry: [
          Commanded.Registration,
          Commanded.Registration.LocalRegistry
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
          Commanded.Assertions.EventAssertions
        ]
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
        "Docs" => "https://hexdocs.pm/commanded/"
      }
    ]
  end

  defp aliases do
    []
  end
end
