# Cluster

EventStore supports running on a cluster of nodes. It uses the [Swarm](https://hex.pm/packages/swarm) library for process distribution.

## Running on a cluster

  1. Add `:swarm` as a dependency in your `mix.exs` file:

      ```elixir
      defp deps do
        [
          {:swarm, "~> 3.0"},
        ]
      end
      ```

  2. Fetch the dependencies:

      ```console
      $ mix deps.get
      ```

  3. Configure the EventStore to use the `:distributed` registry in the environment config (e.g. `config/config.exs`):

      ```elixir
      config :eventstore,
        registry: :distributed
      ```

  4. Swarm must be configured to use the `Swarm.Distribution.StaticQuorumRing` distribution strategy:

      ```elixir
      config :swarm,
        nodes: [:"node1@127.0.0.1", :"node2@127.0.0.1", :"node3@127.0.0.1"],
        node_blacklist: [~r/^primary@.+$/],
        distribution_strategy: Swarm.Distribution.StaticQuorumRing,
        static_quorum_size: 2,
        sync_nodes_timeout: 0,
        debug: false
      ```

    This is to ensure consistency during a network partition. The `static_quorum_size` setting defines the minimum number of nodes that must be connected in the cluster to allow process registration and distribution. If there are fewer nodes currently available than the quorum size, any calls to the `EventStore` will block until enough nodes have started.

## Automatic cluster formation

Swarm can be used with [libcluster](https://github.com/bitwalker/libcluster), a library that provides a mechanism for automatically forming clusters of Erlang nodes, with either static or dynamic node membership.

You will need to include `libcluster` as an additional dependency:

```elixir
defp deps do
  [{:libcluster, "~> 2.2"}]
end
```

Then configure the cluster topology in the environment config (e.g. `config/config.exs`). An example is shown below using the standard Erlang `epmd` daemon strategy:

```elixir
config :libcluster,
  topologies: [
    example: [
      strategy: Cluster.Strategy.Epmd,
      config: [hosts: [:"node1@127.0.0.1", :"node2@127.0.0.1", :"node3@127.0.0.1"]],
    ]
  ]
```

Please refer to the [libcluster docs](https://hexdocs.pm/libcluster/) for more detail.

### Starting a cluster

  1. Run an [Erlang Port Mapper Daemon](http://erlang.org/doc/man/epmd.html) (epmd):

      ```console
      $ epmd -d
      ```

  2. Start an `iex` console per node:

      ```console
      $ MIX_ENV=distributed iex --name node1@127.0.0.1 -S mix
      ```

      ```console
      $ MIX_ENV=distributed iex --name node2@127.0.0.1 -S mix
      ```

      ```console
      $ MIX_ENV=distributed iex --name node3@127.0.0.1 -S mix
      ```

The cluster will be automatically formed as soon as the nodes start.     

## Static cluster topology and formation

Instead of using `libcluster` you can configure the `:kernel` application to wait for cluster formation before starting your application during node start up. This approach is useful when you have a static cluster topology that can be defined in config.

The `sync_nodes_optional` configuration specifies which nodes to attempt to connect to within the `sync_nodes_timeout` window, defined in milliseconds, before continuing with startup. There is also a `sync_nodes_mandatory` setting which can be used to enforce all nodes are connected within the timeout window or else the node terminates.

Each node requires its own individual configuration, listing the other nodes in the cluster:

```elixir
# node1 config
config :kernel,
  sync_nodes_optional: [:"node2@192.168.1.1", :"node3@192.168.1.2"],
  sync_nodes_timeout: 30_000
```

The `sync_nodes_timeout` can be configured as `:infinity` to wait indefinitely for all nodes to
connect. All involved nodes must have the same value for `sync_nodes_timeout`.

This approach will only work for Elixir releases. You will need to use [Erlang's `sys.config`](http://erlang.org/doc/man/config.html) file for development purposes.

The Erlang equivalent of the `:kernerl` mix config, as above, is:

```erlang
% node1.sys.config
[{kernel,
  [
    {sync_nodes_optional, ['node2@127.0.0.1', 'node3@127.0.0.1']},
    {sync_nodes_timeout, 30000}
  ]}
].
```

### Starting a cluster

  1. Run an [Erlang Port Mapper Daemon](http://erlang.org/doc/man/epmd.html) (epmd):

      ```console
      $ epmd -d
      ```

  2. Start an `iex` console per node:

      ```console
      $ MIX_ENV=distributed iex --name node1@127.0.0.1 --erl "-config cluster/node1.sys.config" -S mix
      ```

      ```console
      $ MIX_ENV=distributed iex --name node2@127.0.0.1 --erl "-config cluster/node2.sys.config" -S mix
      ```

      ```console
      $ MIX_ENV=distributed iex --name node3@127.0.0.1 --erl "-config cluster/node3.sys.config" -S mix
      ```

The node specific `<node>.sys.config` files ensure the cluster is formed before starting the `:eventstore` application, assuming this occurs within the 30 seconds timeout.

Once the cluster has formed, you can use the EventStore API from any node. Stream processes will be distributed amongst the cluster and moved around on node up/down.

## Usage

### Append events to a stream

```elixir
stream_uuid = UUID.uuid4()
events = EventStore.EventFactory.create_events(3)

:ok = EventStore.append_to_stream(stream_uuid, 0, events)
```

### Read all events

```elixir
recorded_events = EventStore.stream_all_forward() |> Enum.to_list()
```

### Subscribe to all Streams

```elixir
{:ok, subscription} = EventStore.subscribe_to_all_streams("example-subscription", self(), start_from: :origin)

receive do
  {:events, events} ->
    IO.puts "Received events: #{inspect events}"
    EventStore.ack(subscription, events)

  reply ->
    IO.puts reply
end
```

## Cluster diagnostics

Peek into the Swarm process registry:

```elixir
Swarm.Registry.registered()
```

Discover which node a stream process is running on:

```elixir
stream_uuid |> EventStore.Streams.Stream.name() |> Swarm.whereis_name() |> node()
```
