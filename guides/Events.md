# Events

## Domain events

Domain events indicate that something of importance has occurred, within the context of an aggregate. They **should** be named in the past tense: account registered; funds transferred; fraudulent activity detected etc.

Create a module per domain event and define the fields with `defstruct`. An event **should contain** a field to uniquely identify the aggregate instance (e.g. `account_number`).

Remember to derive the `Jason.Encoder` protocol for the event struct to ensure JSON serialization is supported, as shown below.

```elixir
defmodule BankAccountOpened do
  @derive Jason.Encoder
  defstruct [:account_number, :initial_balance]
end
```

Note, due to event serialization you should expect that only: strings, numbers and boolean values defined in an event are preserved; any other value will be converted to a string. You can control this behaviour as described in the [Serialization guide](https://hexdocs.pm/commanded/serialization.html).

## Event handlers

Event handlers allow you to execute code that reacts to domain events: to build read model projections; dispatch commands to other aggregates; and to interact with third-party systems such as sending emails.

Commanded guarantees only one instance of an event handler will run, regardless of how many nodes are running (even when not using distributed Erlang). This is enforced by the event store subscription (PostgreSQL advisory locks in Elixir Event Store).

Use the `Commanded.Event.Handler` macro within your event handler module to implement the defined behaviour. This consists of a single `handle/2` function that receives each published domain event and its metadata, including the event's unique event number. It should return `:ok` on success or `{:error, :reason}` on failure. You can return `{:error, :already_seen_event}` to skip events that have already been handled, due to the at-least-once event delivery of the supported event stores.

Use pattern matching to match on each type of event you are interested in. A catch-all `handle/2` function is included, so all other events will be ignored by default.

```elixir
defmodule ExampleHandler do
  use Commanded.Event.Handler,
    application: ExampleApp,
    name: "ExampleHandler"

  def handle(%AnEvent{..}, _metadata) do
    # ... process the event
    :ok
  end
end
```

The name given to the event handler **must be** unique and remain unchanged between releases. It is used when subscribing to the event store to track which events the handler has seen during restarts.

```elixir
{:ok, _handler} = ExampleHandler.start_link()
```

### Subscription options

You can choose to start the event handler's event store subscription from the `:origin`, `:current` position, or an exact event number using the `start_from` option. The default is to use the origin so your handler will receive all events.

```elixir
defmodule ExampleHandler do
  # Define `start_from` as one of :origin, :current, or an explicit event number (e.g. 1234)
  use Commanded.Event.Handler,
    application: ExampleApp,
    name: "ExampleHandler",
    start_from: :origin
end
```

You can optionally override `:start_from` by passing it as param:

```elixir
{:ok, _handler} = ExampleHandler.start_link(start_from: :current)
```

Use the `:current` position when you don't want newly created event handlers to go through all previous events. An example would be adding an event handler to send transactional emails to an already deployed system containing many historical events.

You should start your event handlers using an OTP `Supervisor` to ensure they are restarted on error. See the [Supervision guide](https://hexdocs.pm/commanded/supervision.html) for more details.

### Subscribing to an individual stream

By default event handlers will subscribe to all events appended to any stream. Provide a `subscribe_to` option to subscribe to a single stream.

```elixir
defmodule ExampleHandler do
  use Commanded.Event.Handler,
    application: ExampleApp,
    name: __MODULE__,
    subscribe_to: "stream1234"
end
```

This will ensure the handler only receives events appended to that stream.

### Event handler callbacks

- `c:Commanded.Event.Handler.init/1` - (optional) used to configure the handler before it starts.
- `c:Commanded.Event.Handler.after_start/1` - (optional) initialisation callback function called in the process of the started handler.
- `c:Commanded.Event.Handler.error/3` - (optional) called when an event handle/2 callback returns an error.

### Metadata

The `handle/2` function in your handler receives the domain event and a map of metadata associated with that event. You can provide the metadata key/value pairs when dispatching a command:

```elixir
:ok = ExampleApp.dispatch(command, metadata: %{"issuer_id" => issuer_id, "user_id" => "user@example.com"})
```

In addition to the metadata key/values you provide, the following system values will be included in the metadata passed to an event handler:

- `application` - the `Commanded.Application` associated with the event handler.
- `handler_name` - the name of the event handler.
- `state` - optional event handler state.
- `event_id` - a globally unique UUID to identify the event.
- `event_number` - a globally unique, monotonically incrementing and gapless integer used to order the event amongst all events.
- `stream_id` - the stream identity for the event.
- `stream_version` - the version of the stream for the event.
- `causation_id` - an optional UUID identifier used to identify which command caused the event.
- `correlation_id` - an optional UUID identifier used to correlate related commands/events.
- `created_at` - the datetime, in UTC, indicating when the event was created.

These key/value metadata pairs will use atom keys to differentiate them from the user provided metadata:

```elixir
defmodule ExampleHandler do
  use Commanded.Event.Handler,
    application: ExampleApp,
    name: "ExampleHandler"

  def handle(event, metadata) do
    IO.inspect(metadata)
    # %{
    #   :causation_id => "db1ebd30-7d3c-40f7-87cd-12cd9966df32",
    #   :correlation_id => "1599630b-9c38-433c-9548-0dd793108ba0",
    #   :created_at => #DateTime<2017-10-30 11:19:56.178901Z>,
    #   :event_id => "5e4a0f38-385b-4d57-823b-a1bcf705b7bb",
    #   :event_number => 12345,
    #   :stream_id => "e42a588d-2cda-4314-a471-5d008cce01fc",
    #   :stream_version => 1,
    #   "issuer_id" => "0768d69a-d2b7-48f4-d0e9-083a97f7ebe0",
    #   "user_id" => "user@example.com"
    # }

    :ok
  end
end
```

### Consistency guarantee

You can specify an event handler's consistency guarantee using the `consistency` option:

```elixir
defmodule ExampleHandler do
  use Commanded.Event.Handler,
    application: ExampleApp,
    name: "ExampleHandler",
    consistency: :eventual
```

The available options are `:eventual` (default) and `:strong`:

- *Strong consistency* offers up-to-date data but at the cost of high latency.
- *Eventual consistency* offers low latency but read model queries may reply with stale data since they may not have processed the persisted events.

You request the consistency guarantee, either `:strong` or `:eventual`, when dispatching a command. Strong consistency will block the command dispatch and wait for all strongly consistent event handlers to successfully process all events created by the command. Whereas eventual consistency will immediately return after command dispatch, without waiting for any event handlers, even those configured for strong consistency.

### How does it work?

An event handler is a `GenServer` process that subscribes to the configured event store. For each event persisted to the store the `handle/2` callback is called, passing the domain event and its metadata.

## Upcasting events

Commanded supports upcasting of events at runtime using the `Commanded.Event.Upcaster` protocol.

By implementing the upcaster protocol you can transform an event before it is used by a consumer. This might be an aggregate, an event handler, or a process manager. Because the upcaster changes the event at runtime, handlers only need to support the latest version. You can also use upcasting to change the type of event.

### Examples

Change the shape of an event by renaming a field:

```elixir
defimpl Commanded.Event.Upcaster, for: AnEvent do
  def upcast(%AnEvent{} = event, _metadata) do
    %AnEvent{name: name} = event

    %AnEvent{event | first_name: name}
  end
end
```

Change the type of event by replacing a historical event with a new event:

```elixir
defimpl Commanded.Event.Upcaster, for: HistoricalEvent do
  def upcast(%HistoricalEvent{} = event, _metadata) do
    %HistoricalEvent{id: id, name: name} = event

    %NewEvent{id: id, name: name}
  end
end
```

## Reset an EventHandler

An event handler can be reset (using a mix task), it will restart the event store subscription from the configured
`start_from`. This allow an individual handler to be restart while the app is still running.

You can define a `before_reset/1` function that will be called before resetting the event handler.

```elixir
defmodule ExampleHandler do
  use Commanded.Event.Handler,
    application: ExampleApp,
    name: __MODULE__

  require Logger

  alias Commanded.Event.FailureContext

  def before_reset do
    # Do something
    :ok
  end
end
```
