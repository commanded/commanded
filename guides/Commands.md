# Command registration and dispatch

## Commands

You need to create a module per command and define the fields using `defstruct`:

```elixir
defmodule OpenAccount do
  defstruct [:account_number, :initial_balance]
end
```

A command **must contain** a field to uniquely identify the aggregate instance (e.g. `account_number`).

## Command dispatch and routing

A router module is used to route and dispatch commands to their registered command handler or aggregate module.

You create a router module, using `Commanded.Commands.Router`, and register each command with its associated handler:

```elixir
defmodule BankRouter do
  use Commanded.Commands.Router

  dispatch OpenAccount, to: OpenAccountHandler, aggregate: BankAccount, identity: :account_number
  dispatch DepositMoney, to: DepositMoneyHandler, aggregate: BankAccount, identity: :account_number
end
```

This can be more succinctly configured by excluding command handlers and [dispatching directly to the aggregate root](#dispatch-directly-to-aggregate), using [multi-command registration](#multi-command-registration), and with the [`identify`](#define-aggregate-identity) helper macro:

```elixir
defmodule BankRouter do
  use Commanded.Commands.Router

  identify BankAccount, by: :account_number
  dispatch [OpenAccount, DepositMoney], to: BankAccount
end
```

## Command handlers

A command handler receives the aggregate root and the command being executed. It allows you to validate, authorize, and/or enrich the command with additional data before executing the appropriate aggregate root module function.

The command handler must implement the `Commanded.Commands.Handler` behaviour consisting of a single `handle/2` function. It receives the aggregate root state and the command to be handled. It must return the raised domain events from the aggregate root. It may return an `{:error, reason}` tuple on failure.

```elixir
defmodule OpenAccountHandler do
  @behaviour Commanded.Commands.Handler

  def handle(%BankAccount{} = aggregate, %OpenAccount{account_number: account_number, initial_balance: initial_balance}) do
    aggregate
    |> BankAccount.open_account(account_number, initial_balance)
  end
end
```

Command handlers execute in the context of the dispatch call, as such they are limited to the timeout period specified. The default timeout is five seconds, the same as a `GenServer` call. You can increase the timeout value for individual commands as required - see the section on [Timeouts](#timeouts) below.

### Dispatch directly to aggregate

It is also possible to route a command directly to an aggregate root, without requiring an intermediate command handler.

```elixir
defmodule BankRouter do
  use Commanded.Commands.Router

  dispatch OpenAccount, to: BankAccount, identity: :account_number
end
```

The aggregate root must implement an `execute/2` function that receives the aggregate's state and the command to execute.

### Dispatching commands

You can then dispatch a command using the router:

```elixir
:ok = BankRouter.dispatch(%OpenAccount{account_number: "ACC123", initial_balance: 1_000})
```

### Define aggregate identity

You can define the identity field for an aggregate once using the `identify` macro. The configured identity will be used for all commands registered to the aggregate, unless overridden by a command registration.

#### Example

```elixir
defmodule BankRouter do
  use Commanded.Commands.Router

  identify BankAccount, by: :account_number

  dispatch OpenAccount, to: BankAccount
end
```

An optional identity prefix can be used to distinguish between different aggregates that  would otherwise share the same identity. As an example you might have a `User` and a `UserPreferences` aggregate that you wish to share the same identity. In this scenario you should specify a `prefix` for each aggregate (e.g. "user-" and "user-preference-").

```elixir
defmodule BankRouter do
  use Commanded.Commands.Router

  identify BankAccount,
    by: :account_number,
    prefix: "bank-account-"

  dispatch OpenAccount, to: BankAccount
end
```

The prefix is used as the stream identity when appending, and reading, the aggregate's events.

### Timeouts

A command handler has a default timeout of 5 seconds. The same default as a `GenServer` process call. It must handle the command in this period, otherwise the call fails and the caller exits.

You can configure a different timeout value during command registration by providing a `timeout` option, defined in milliseconds:

```elixir
defmodule BankRouter do
  use Commanded.Commands.Router

  # configure a timeout of 1 second for the open account command handler
  dispatch OpenAccount,
    to: OpenAccountHandler,
    aggregate: BankAccount,
    identity: :account_number,
    timeout: 1_000
end
```

You can override the timeout value during command dispatch. This example is dispatching the open account command with a timeout of 2 seconds:

```elixir
:ok = BankRouter.dispatch(%OpenAccount{account_number: "ACC123", initial_balance: 1_000}, timeout: 2_000)
```

### Multi-command registration

Command routers support multi command registration so you can group related command handlers into the same module:

```elixir
defmodule BankRouter do
  use Commanded.Commands.Router

  dispatch [OpenAccount,CloseAccount],
    to: BankAccountHandler,
    aggregate: BankAccount,
    identity: :account_number
end
```

### Command dispatch consistency guarantee

You can choose the consistency guarantee provided by a command dispatch using the `consistency` option:

```elixir
:ok = BankRouter.dispatch(command, consistency: :strong)
```

The available options are `:eventual` (default) and `:strong`.

- *Strong consistency* offers up-to-date data but at the cost of high latency.
- *Eventual consistency* offers low latency but read model queries may reply with stale data since they may not have processed the persisted events.

When dispatching a command using `consistency: :strong` the dispatch will block until all of the strongly consistent event handlers and process managers have handled all events created by the command. This guarantees that when you receive the `:ok` response from dispatch your strongly consistent read models will have been updated and can safely be queried. Strong consistency helps to alleviate problems and workarounds you would otherwise encounter when dealing with eventual consistency in your own application.

Use `:strong` consistency when you want to query a read model immediately after dispatching a command. You *must* also configure the event handler to use `:strong` consistency. Dispatching a command using `:strong` consistency but without any strongly consistent event handlers configured will have no effect.

Using `:eventual` consistency, or omitting the `consistency` option, will cause the command dispatch to immediately return without waiting for any event handlers. The handlers run independently and asynchronously in the background, therefore you will need to deal with potentially stale read model data.

#### Consistency failures

By opting-in to strong consistency you may encounter an additional error reply from command dispatch:

```elixir
case BankRouter.dispatch(command, consistency: :strong) do
  :ok -> # ... all ok
  {:error, :consistency_timeout} -> # command ok, handlers have not yet executed
end
```

Receiving an `{:error, :consistency_timeout}` error indicates the command successfully dispatched, but some or all of the strongly consistent event handlers have not yet executed.

The default timeout is configured as five seconds; this determines how long the dispatch will block waiting for the handlers. You can override the default value in your environment config file (e.g. `config/config.exs`):

```elixir
config :commanded,
  dispatch_consistency_timeout: 10_000  # ten seconds
```

### Dispatch returning execution result

You can choose to include the execution result as part of the dispatch result by
setting `include_execution_result` true:

```elixir
{
  :ok,
  %Commanded.Commands.ExecutionResult{
    aggregate_uuid: aggregate_uuid,
    aggregate_version: aggregate_version,
    events: events,
    metadata: metadata
  }
} = BankRouter.dispatch(command, include_execution_result: true)
```

You can use this if you need to get information from the events produced by the aggregate without waiting for the events to be projected.

### Dispatch returning aggregate version

You can optionally choose to include the aggregate's version as part of the dispatch result by setting the  `include_aggregate_version` option to true:

```elixir
{:ok, aggregate_version} = BankRouter.dispatch(command, include_aggregate_version: true)
```

This is useful when you need to wait for an event handler, such as a read model projection, to be up-to-date before continuing execution or querying its data.

### Correlation and causation ids

To assist with monitoring and debugging your deployed application it is useful to track the causation and correlation ids for your commands and events.

- `causation_id` - the UUID of the command causing an event, or the event causing a command dispatch.
- `correlation_id` - a UUID used to correlate related commands/events.

You can set causation and correlation ids when dispatching a command:

```elixir
:ok = ExampleRouter.dispatch(command, causation_id: UUID.uuid4(), correlation_id: UUID.uuid4())
```

When dispatching a command in an event handler, you should copying these values from the event your are processing:

```elixir
defmodule ExampleHandler do
  use Commanded.Event.Handler, name: "ExampleHandler"

  def handle(%AnEvent{..}, %{event_id: causation_id, correlation_id: correlation_id}) do
    ExampleRouter.dispatch(%ExampleCommand{..},
      causation_id: causation_id,
      correlation_id: correlation_id,
    )
  end
end
```

Commands dispatched by a process manager will be automatically assigned the appropriate causation and correlation ids from the source domain event.

You can use [Commanded audit middleware](https://github.com/commanded/commanded-audit-middleware) to record every dispatched command. This allows you to follow the chain of commands and events by using the causation id. The correlation id can be used to find all related commands and events.

### Event metadata

It's helpful for debugging to have additional metadata associated with events issued by a command. You can set it when dispatching a command:

```elixir
:ok = ExampleRouter.dispatch(command, metadata: %{"issuer_id" => issuer_id, "user_id" => "user@example.com"})
```

Note, due metadata serialization you should expect that only: strings, numbers and boolean values are preserved; any other value will be converted to a string.

You should always use string keys in your metadata map. If you use atom keys they will be converted to string.

In addition to the metadata key/values you provide, the following system values will be included when metadata is passed to an event handler:

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

### Aggregate lifespan

By default an aggregate instance process will run indefinitely once started. You can control this by implementing the `Commanded.Aggregates.AggregateLifespan` behaviour in a module.

```elixir
defmodule BankAccountLifespan do
  @behaviour Commanded.Aggregates.AggregateLifespan

  def after_command(%OpenAccount{}), do: :infinity
  def after_command(%CloseAccount{}), do: 0
end
```

Then specify the module as the `lifespan` option when registering the command in the router.

```elixir
defmodule BankRouter do
  use Commanded.Commands.Router

  dispatch [OpenAccount,CloseAccount],
    to: BankAccount,
    lifespan: BankAccountLifespan,
    identity: :account_number
end
```

The timeout is specified in milliseconds, after which time the aggregate process will be stopped if no other messages are received.

You can also return `:hibernate` and the process is hibernated, it will continue its loop once a message is in its message queue. Hibernating an aggregate causes garbage collection and minimises the memory used by the process. Hibernating should not be used aggressively as too much time could be spent garbage collecting.

Return `:infinity` to keep the aggregate instance process running indefinitely.

## Middleware

Allows a command router to define middleware modules that are executed before and after success or failure of each command dispatch.

This provides an extension point to add in command validation, authorization, logging, and other behaviour that you want to be called for every command the router dispatches.

```elixir
defmodule BankingRouter do
  use Commanded.Commands.Router

  middleware CommandLogger
  middleware MyCommandValidator
  middleware AuthorizeCommand

  identify BankAccount, by: :account_number

  dispatch OpenAccount, to: OpenAccountHandler, aggregate: BankAccount
  dispatch DepositMoney, to: DepositMoneyHandler, aggregate: BankAccount
end
```

The middleware modules are executed in the order they’ve been defined. They will receive a `Commanded.Middleware.Pipeline` struct containing the command being dispatched.

### Example middleware

Implement the `Commanded.Middleware` behaviour in your module and define the `before_dispatch`, `after_dispatch`, and `after_failure` callback functions.

```elixir
defmodule NoOpMiddleware do
  @behaviour Commanded.Middleware

  alias Commanded.Middleware.Pipeline
  import Pipeline

  def before_dispatch(%Pipeline{command: command} = pipeline) do
    pipeline
  end

  def after_dispatch(%Pipeline{} = pipeline) do
    pipeline
  end

  def after_failure(%Pipeline{} = pipeline) do
    pipeline
  end
end
```

Commanded provides a `Commanded.Middleware.Logger` middleware for logging the name of each dispatched command and its execution duration.
