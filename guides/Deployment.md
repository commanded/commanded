# Deployment

Commanded supports running on a single node, or multiple nodes run as either a [distributed Erlang](http://erlang.org/doc/reference_manual/distributed.html) cluster or as multiple single instance nodes.

## Single node deployment

Running your app using Commanded on a single node requires no configuration as local is the default setting.

## Multi node distributed Erlang deployment

To support deployment to a cluster of nodes and distributed Erlang you must configure:

1. A registry which supports distributed Erlang. The `:global` registry provided by Commanded or the [Commanded Swarm registry](https://github.com/commanded/commanded-swarm-registry) library.
2. [Phoenix's distributed pub/sub and presence platform](https://hex.pm/packages/phoenix_pubsub) to allow process distribution and communication amongst all nodes in the cluster.

### `:global` registry

Use Erlang's [`:global`](http://erlang.org/doc/man/global.html) name registration facility with distributed Erlang. The global name server starts automatically when a node is started. The registered names are stored in replicated global name tables on every node. Thus, the translation of a name to a pid is fast, as it is always done locally.

Define the `:global` registry for your application:

```elixir
defmodule MyApp.Application do
  use Commanded.Application,
    otp_app: :my_app,
    event_store: [
      adapter: Commanded.EventStore.Adapters.EventStore,
      event_store: MyApp.EventStore
    ],
    registry: :global
end
```

Or configure your application to use the `:global` registry in config:

```elixir
# config/config.exs
config :my_app, MyApp.Application, registry: :global
```

Note that when clusters are formed dynamically (e.g. using [libcluster](https://hex.pm/packages/libcluster)]), the typical sequence of events is that first all nodes will start all processes, then the cluster is formed and `:global` will kill off duplicate names. This is ugly in the logs but expected; it also means that if your supervisor's `:max_restarts` is too low - lower than the number of event handlers/projectors you start - it will immediately exit and if that was your
application supervisor, your app gets shutdown. The solution is simple: keep `:max_restarts` above the number of event handlers you start under your supervisor and the transition from no cluster to cluster will be clean. 

### Commanded Swarm registry

Add `commanded_swarm_registry` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [{:commanded_swarm_registry, "~> 1.0"}]
end
```

Fetch mix dependencies:

```console
$ mix deps.get
```

Configure your application to use the Swarm registry:

```elixir
# config/config.exs
config :my_app, MyApp.Application, registry: Commanded.Registration.SwarmRegistry
```

This uses the [Swarm](https://hex.pm/packages/swarm) to distribute processes amongst the available nodes in the cluster.

### Phoenix pub/sub

First, add it as a dependency to your project's `mix.exs` file:

```elixir
defp deps do
  [{:phoenix_pubsub, "~> 2.0"}]
end
```

Fetch mix dependencies and configure the pubsub settings for your application in the environment config file:

```elixir
# config/config.exs
config :my_app, MyApp.Application,
  pubsub: [
    phoenix_pubsub: [
      adapter: Phoenix.PubSub.PG2,
      pool_size: 1
    ]
  ]
```

The PG2 adapter is preferable for cluster deployment since it is provided by Erlang and requires no further dependencies.

### EventStore

If using PostgreSQL-based Elixir EventStore please also refer to its documentation about [running on a clustering of nodes](https://hexdocs.pm/eventstore/cluster.html).

## Multi-node, but not distributed Erlang deployment

Running multiple nodes, but choosing not to connect the nodes together to form a distributed Erlang cluster, requires that you use the local registry and Phoenix's pub/sub library with its Redis adapter.

You must install and use Phoenix's pub/sub library, [as described above](#phoenix-pub-sub).

Since the nodes aren't connected, you are required to use the Redis adapter as a way of communicating between the nodes. Therefore you will need to host a Redis instance for use by your app.

```elixir
# config/config.exs
config :my_app, MyApp.Application,
  registry: :local,
  pubsub: [
    phoenix_pubsub: [
      adapter: Phoenix.PubSub.Redis,
      host: "localhost",
      port: 6379,
      node_name: "localhost"
    ]
  ]
```
