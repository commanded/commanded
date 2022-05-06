defmodule Commanded do
  @moduledoc """
  Use Commanded to build your own Elixir applications following the CQRS/ES pattern.

  Provides support for:

  - [Defining applications](application.html).
  - [Command registration and dispatch](commands.html).
  - [Hosting and delegation to aggregates](aggregates.html).
  - [Event handling](events.html).
  - [Long running process managers](process-managers.html).

  Use Commanded with one of the following event stores for persistence:

  - Elixir [EventStore](https://hex.pm/packages/eventstore) using Postgres for persistence
  - [EventStoreDB](https://www.eventstore.com/)

  Please check the [Getting Started](getting-started.html) and [Usage](usage.html) guides to learn more.
  """

  use Application

  alias Commanded.Aggregates.Aggregate
  alias Commanded.Application.Config

  @doc false
  def start(_type, _args) do
    children = [
      Config
    ]

    opts = [strategy: :one_for_one, name: Commanded.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @doc """
  Retrieve aggregate state of an aggregate.

  Retrieving aggregate state is done by calling to the opened aggregate,
  or querying the event store for an optional state snapshot
  and then replaying the aggregate's event stream.
  """
  @spec aggregate_state(
          application :: Commanded.Application.t(),
          aggregate_module :: module(),
          aggregate_uuid :: Aggregate.uuid(),
          timeout :: integer
        ) :: Aggregate.state()
  def aggregate_state(application, aggregate_module, aggregate_uuid, timeout \\ 5_000) do
    Aggregate.aggregate_state(
      application,
      aggregate_module,
      aggregate_uuid,
      timeout
    )
  end
end
