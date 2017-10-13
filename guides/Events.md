# Event handling

## Domain events

Domain events indicate that something of importance has occurred, within the context of an aggregate. They are named in the past tense: account registered; funds transferred; fraudulent activity detected.

Create a module per domain event and define the fields with `defstruct`. An event **should contain** a field to uniquely identify the aggregate instance (e.g. `account_number`).

```elixir
defmodule BankAccountOpened do
  defstruct [:account_number, :initial_balance]
end
```

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
