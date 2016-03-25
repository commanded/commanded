defmodule Commanded.Mixfile do
  use Mix.Project

  def project do
    [app: :commanded,
     version: "0.0.1",
     elixir: "~> 1.2",
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     deps: deps]
  end

  def application do
    [
      applications: [
        :logger,
        :eventstore
      ]
    ]
  end

  defp deps do
    [
      {:eventstore, github: "slashdotdash/eventstore", only: :dev},
    ]
  end
end
