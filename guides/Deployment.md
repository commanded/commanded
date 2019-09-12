# Deployment

Commanded supports running on a single node, or multiple nodes run as either a [distributed Erlang](http://erlang.org/doc/reference_manual/distributed.html) cluster or as multiple single instance nodes.

## Single node deployment

Running your app using Commanded on a single node requires no configuration as local is the default setting.

## Multi node cluster deployment

To support deployment to a cluster of nodes you must use the [Commanded Swarm registry](https://github.com/commanded/commanded-swarm-registry) library and [Phoenix's distributed pub/sub and presence platform](https://hex.pm/packages/phoenix_pubsub) to allow process distribution and communication amongst all nodes in the cluster.

### Commanded Swarm registry

Add `commanded_swarm_registry` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:commanded_swarm_registry, "~> 0.1"}
  ]
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

This uses the [Swarm](https://hex.pm/packages/swarm) to distribute process amongst the available nodes in the cluster.

### Phoenix pub/sub

First, add it as a dependency to your project's `mix.exs` file:

```elixir
defp deps do
  [{:phoenix_pubsub, "~> 1.0"}]
end
```

Fetch mix deps and configure the pubsub settings for your application in the environment config file:

```elixir
# `config/config.exs`
config :my_app, MyApp.Application,
  pubsub: [
    phoenix_pubsub: [
      adapter: Phoenix.PubSub.PG2,
      pool_size: 1
    ]
  ]
```

The PG2 adapter is preferable for cluster deployment since it is provided by Erlang and requires no further dependencies.

## Multi node, but not clustered deployment

Running multiple nodes, but choosing not to connect the nodes together to form a cluster, requires that you use the local registry and Phoenix's pub/sub library with its Redis adapter.

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
