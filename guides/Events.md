# Event handling

## Domain events

Domain events indicate that something of importance has occurred, within the context of an aggregate. They are named in the past tense: account registered; funds transferred; fraudulent activity detected.

Create a module per domain event and define the fields with `defstruct`. An event **should contain** a field to uniquely identify the aggregate instance (e.g. `account_number`).

```elixir
defmodule BankAccountOpened do
  defstruct [:account_number, :initial_balance]
end
```

Note, due to event serialization you should expect that only: strings, numbers and boolean values defined in an event are preserved; any other value will be converted to a string. You can control this behaviour as described in serialization section.

## Event handlers

Use the `Commanded.Event.Handler` macro within your event handler module to implement the defined behaviour. This consists of a single `handle/2` function that receives each published domain event and its metadata, including the event's unique event number. It should return `:ok` on success or `{:error, :reason}` on failure. You can return `{:error, :already_seen_event}` to skip events that have already been handled, due to the at-least-once event delivery of the supported event stores.

Use pattern matching to match on each type of event you are interested in. A catch-all `handle/2` function is included, so all other events will be ignored by default.

```elixir
defmodule AccountBalanceHandler do
  use Commanded.Event.Handler, name: "account_balance"

  def init do
    with {:ok, _} <- Agent.start_link(fn -> 0 end, name: AccountBalance) do
      :ok
    end
  end

  def handle(%BankAccountOpened{initial_balance: initial_balance}, _metadata) do
    Agent.update(AccountBalance, fn _ -> initial_balance end)
  end

  def handle(%MoneyDeposited{balance: balance}, _metadata) do
    Agent.update(AccountBalance, fn _ -> balance end)
  end

  def current_balance do
    Agent.get(AccountBalance, fn balance -> balance end)
  end
end
```

The name given to the event handler **must be** unique and remain unchanged between releases. It is used when subscribing to the event store to track which events the handler has seen during restarts.

```elixir
{:ok, _handler} = AccountBalanceHandler.start_link()
```

You can choose to start the event handler's event store subscription from the `:origin`, `:current` position or an exact event number using the `start_from` option. The default is to use the origin so your handler will receive all events.

```elixir
# start from :origin, :current, or an explicit event number (e.g. 1234)
defmodule AccountBalanceHandler do
  use Commanded.Event.Handler, name: "account_balance", start_from: :origin

  # ...
end

# You can optionally override :start_from by passing it as param
{:ok, _handler} = AccountBalanceHandler.start_link(start_from: :current)
```

Use the `:current` position when you don't want newly created event handlers to go through all previous events. An example would be adding an event handler to send transactional emails to an already deployed system containing many historical events.

You should start your event handlers using a [supervisor](#supervision) to ensure they are restarted on error.

### Metadata

The `handle/2` function in your handler receives the domain event and a map of metadata associated with that event. You can provide the metadata key/value pairs when dispatching a command:

```elixir
:ok = ExampleRouter.dispatch(command, metadata: %{"issuer_id" => issuer_id, "user_id" => "user@example.com"})
```

In addition to the metadata key/values you provide, the following system values will be included in the metadata passed to an event handler:

- `event_id` - a globally unique UUID to identify the event.
- `event_number` - a globally unique, monotonically incrementing and gapless integer used to order the event amongst all events.
- `stream_id` - the stream identity for the event.
- `stream_version` - the version of the stream for the event.
- `causation_id` - an optional UUID identifier used to identify which command caused the event.
- `correlation_id` - an optional UUID identifier used to correlate related commands/events.
- `created_at` - the date/time, in UTC, indicating when the event was created.

These key/value metadata pairs will use atom keys to differentiate them from the user provided metadata:

```elixir
defmodule ExampleHandler do
  use Commanded.Event.Handler, name: "ExampleHandler"

  def handle(event, metadata) do
    IO.inspect(metadata)
    # %{
    #   :causation_id => "db1ebd30-7d3c-40f7-87cd-12cd9966df32",
    #   :correlation_id => "1599630b-9c38-433c-9548-0dd793108ba0",
    #   :created_at => ~N[2017-10-30 11:19:56.178901],
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
defmodule AccountBalanceHandler do
  use Commanded.Event.Handler,
    name: "account_balance",
    consistency: :eventual
```

The available options are `:eventual` (default) and `:strong`:

- *Strong consistency* offers up-to-date data but at the cost of high latency.
- *Eventual consistency* offers low latency but read model queries may reply with stale data since they may not have processed the persisted events.

You request the consistency guarantee, either `:strong` or `:eventual`, when dispatching a command. Strong consistency will block the command dispatch and wait for all strongly consistent event handlers to successfully process all events created by the command. Whereas eventual consistency will immediately return after command dispatch, without waiting for any event handlers, even those configured for strong consistency.
