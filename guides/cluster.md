# Cluster

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

The node specific `<node>.sys.config` files ensure the cluster is formed before starting the `:eventstore` application, assuming this occurs within the 30 seconds timeout. Once running, you can use the Event Store API from any node. Stream processes will be distributed amongst the cluster and moved around on node up/down.

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
