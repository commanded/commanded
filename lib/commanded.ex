defmodule Commanded do
  @moduledoc """
  Use Commanded to build your own Elixir applications following the CQRS/ES pattern.

  Provides support for:

  - [Command registration and dispatch](commands.html).
  - [Hosting and delegation to aggregates](aggregates.html).
  - [Event handling](events.html).
  - [Long running process managers](process-managers.html).

  Use Commanded with one of the following event stores for persistence:

  - [EventStore](https://hex.pm/packages/eventstore) Elixir library, using PostgreSQL for persistence
  - Greg Young's [Event Store](https://eventstore.org/).

  Please check the [Getting Started](getting-started.html) and [Usage](usage.html) guides to learn more.
  """

  use Application

  def start(_type, _args) do
    children = [
      Commanded.Application.Config
    ]

    opts = [strategy: :one_for_one, name: Commanded.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
