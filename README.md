# Commanded

Use Commanded to build your own Elixir applications following the [CQRS/ES](http://cqrs.nu/Faq) pattern.

Provides support for:

- Command registration and dispatch.
- Hosting and delegation to aggregate roots.
- Event handling.
- Long running process managers.

Use with one of the following event stores for persistence:

- [EventStore](https://github.com/slashdotdash/eventstore) Elixir library, using PostgreSQL for persistence
- Greg Young's [Event Store](https://geteventstore.com/).

---

- [Changelog](CHANGELOG.md) 
- [Wiki](/slashdotdash/commanded/wiki) 
- [Frequently asked questions](/slashdotdash/commanded/wiki/FAQ)
- [Getting help](/slashdotdash/commanded/wiki/Getting-help)

MIT License

[![Build Status](https://travis-ci.org/slashdotdash/commanded.svg?branch=master)](https://travis-ci.org/slashdotdash/commanded) [![Join the chat at https://gitter.im/commanded/Lobby](https://badges.gitter.im/commanded/Lobby.svg)](https://gitter.im/commanded/Lobby?utm_source=badge&utm_medium=badge&utm_campaign=pr-badge&utm_content=badge)

---

### Overview

- [Getting started](#getting-started)
- [Choosing an event store](#choosing-an-event-store)
  - [PostgreSQL-based EventStore](#postgresql-based-eventstore)
  - [Greg Young's Event Store](#greg-youngs-event-store)
- [Sample usage](#sample-usage)
  - [Aggregate roots](#aggregate-roots)
  - [Commands](#commands)
    - [Command handlers](#command-handlers)
    - [Command dispatch and routing](#command-dispatch-and-routing)
    - [Aggregate lifespan](#aggregate-lifespan)
    - [Middleware](#middleware)
  - [Events](#events)
    - [Event handlers](#event-handlers)
  - [Process managers](#process-managers)
  - [Supervision](#supervision)
  - [Serialization](#serialization)
- [Read model projections](#read-model-projections)
- [Used in production?](#used-in-production)
- [Event store provider](#event-store-provider)
- [Contributing](#contributing)
- [Need help?](#need-help)

## Getting started

The package can be installed from hex as follows.

1. Add `commanded` to your list of dependencies in `mix.exs`:

    ```elixir
    def deps do
      [{:commanded, "~> 0.13"}]
    end
    ```

## Choosing an event store

You must decide which event store to use with Commanded. You have a choice between two existing event store adapters:

- PostgreSQL-based [EventStore](https://github.com/slashdotdash/eventstore) using the [commanded_eventstore_adapter](https://github.com/slashdotdash/commanded-eventstore-adapter) package.

- Greg Young's [Event Store](https://geteventstore.com/) using the [commanded_extreme_adapter](https://github.com/slashdotdash/commanded-extreme-adapter) package.

Want to use a different event store? Then you will need to write your own [event store provider](#event-store-provider).

### PostgreSQL-based EventStore

[EventStore](https://github.com/slashdotdash/eventstore) is an open-source event store using PostgreSQL for persistence, implemented in Elixir.

1. Add `commanded_eventstore_adapter` to your list of dependencies in `mix.exs`:

    ```elixir
    def deps do
      [{:commanded_eventstore_adapter, "~> 0.1"}]
    end
    ```

2. Include `:eventstore` in the list of applications to start.

    For **Elixir 1.4**, add `:eventstore` to the extra applications list in `mix.exs`:

    ```elixir
    def application do
      [
        extra_applications: [
          :logger,
          :eventstore,
        ],
        # ...
      ]
    end
    ```

    For **Elixir 1.3** and before, add `:eventstore` to the applications list in `mix.exs`:

    ```elixir
    def application do
      [
        applications: [
          :logger,
          :eventstore,
        ],
        # ...
      ]
    end
    ```

3. Configure Commanded to use the event store adapter:

    ```elixir
    config :commanded,
      event_store_adapter: Commanded.EventStore.Adapters.EventStore
    ```

4. Configure the `eventstore` in each environment's mix config file (e.g. `config/dev.exs`), specifying usage of the included JSON serializer:

    ```elixir
    config :eventstore, EventStore.Storage,
      serializer: Commanded.Serialization.JsonSerializer,
      username: "postgres",
      password: "postgres",
      database: "eventstore_dev",
      hostname: "localhost",
      pool_size: 10
    ```

5. Create the `eventstore` database and tables using the `mix` task.

    ```console
    $ mix event_store.create
    ```

6. Force a (re)compile of the commanded dependency to include the adapter:

    ```console
    $ mix deps.compile commanded --force
    ```

### Greg Young's Event Store

Greg's [Event Store](https://geteventstore.com/) is an open-source, functional database with Complex Event Processing in JavaScript. It can run as a cluster of nodes containing the same data, which remains available for writes provided at least half the nodes are alive and connected.

This adapter uses the [Extreme](https://github.com/exponentially/extreme) Elixir TCP client to connect to the Event Store.

1. Add `commanded_extreme_adapter` to your list of dependencies in `mix.exs`:

    ```elixir
    def deps do
      [{:commanded_extreme_adapter, "~> 0.1"}]
    end
    ```

2. Configure Commanded to use the event store adapter:

    ```elixir
    config :commanded,
      event_store_adapter: Commanded.EventStore.Adapters.Extreme
    ```

3. Configure the `extreme` library connection with your event store connection details:

    ```elixir
    config :extreme, :event_store,
      db_type: :node,
      host: "localhost",
      port: 1113,
      username: "admin",
      password: "changeit",
      reconnect_delay: 2_000,
      max_attempts: :infinity
    ```

4. Configure the `commanded_extreme_adapter` to use the JSON serializer and specify a stream prefix to be used by all Commanded event streams:

    ```elixir
    config :commanded_extreme_adapter,
      serializer: Commanded.Serialization.JsonSerializer,
      stream_prefix: "commandeddev"
    ```

    The stream prefix **must not** contain a dash character ("-"). This is used for category projections and event handler subscriptions.

5. Force a (re)compile of the commanded dependency to include the adapter:

    ```console
    $ mix deps.compile commanded --force
    ```

You **must** run the Event Store with all projections enabled and standard projections started. Use the `--run-projections=all --start-standard-projections=true` flags when running the Event Store executable.


#### Changing event store adapters

**Note** To switch between an event store adapter you *must* recompile the Commanded dependency:

```console
$ mix deps.compile commanded --force
```

For the test environment use: `$ MIX_ENV=test mix deps.compile commanded --force`

## Sample usage

Including `commanded` in the applications section of `mix.exs` will ensure it is started.

You may manually start the top level Supervisor process.

```elixir
{:ok, _} = Commanded.Supervisor.start_link
```

### Aggregate roots

Build your aggregate roots using standard Elixir modules and functions, with structs to hold state. There is no external dependency requirement.

An aggregate root is comprised of its state, public command functions, and state mutators.

#### Command functions

A command function receives the aggregate root's state and the command to execute. It must return the resultant domain events. This may be none, one, or multiple events.

For business rule violations and errors you may return an `{:error, reason}` tagged tuple or raise an exception.

#### State mutators

The state of an aggregate root can only be mutated by applying a raised domain event to its state. This is achieved by an `apply/2` function that receives the state and the domain event. It returns the modified state.

Pattern matching is used to invoke the respective `apply/2` function for an event. These functions *must never fail* as they are used when rebuilding the aggregate state from its history of raised domain events. You cannot reject the event once it has occurred.

#### Example aggregate root

```elixir
defmodule BankAccount do
  defstruct [account_number: nil, balance: nil]

  # public command API

  def open_account(%BankAccount{} = account, account_number, initial_balance)
    when initial_balance > 0
  do
    %BankAccountOpened{account_number: account_number, initial_balance: initial_balance}
  end

  def open_account(%BankAccount{} = account, account_number, initial_balance)
    when initial_balance <= 0
  do
    {:error, :initial_balance_must_be_above_zero}
  end

  # state mutators

  def apply(%BankAccount{} = account, %BankAccountOpened{account_number: account_number, initial_balance: initial_balance}) do
    %BankAccount{account |
      account_number: account_number,
      balance: initial_balance
    }
  end
end
```

### Commands

Create a module per command and define the fields with `defstruct`. A command **must contain** a field to uniquely identify the aggregate instance (e.g. `account_number`).

```elixir
defmodule OpenAccount do
  defstruct [:account_number, :initial_balance]
end
```

### Command handlers

Implement the `Commanded.Commands.Handler` behaviour consisting of a single `handle/2` function.

It receives the aggregate root state and the command to be handled. It must return the raised domain events from the aggregate root. It may return an `{:error, reason}` tuple on failure.

```elixir
defmodule OpenAccountHandler do
  @behaviour Commanded.Commands.Handler

  def handle(%BankAccount{} = aggregate, %OpenAccount{account_number: account_number, initial_balance: initial_balance}) do
    aggregate
    |> BankAccount.open_account(account_number, initial_balance)
  end
end
```

### Command dispatch and routing

You must create a router to register each command with its associated handler.

```elixir
defmodule BankRouter do
  use Commanded.Commands.Router

  dispatch OpenAccount, to: OpenAccountHandler, aggregate: BankAccount, identity: :account_number
  dispatch DepositMoney, to: DepositMoneyHandler, aggregate: BankAccount, identity: :account_number
end
```

It is also possible to route a command directly to an aggregate root, without requiring an intermediate command handler.

```elixir
defmodule BankRouter do
  use Commanded.Commands.Router

  dispatch OpenAccount, to: BankAccount, identity: :account_number
end
```

The aggregate root must implement an `execute/2` function that receives the aggregate's state and the command to execute.

You can then dispatch a command using the router.

```elixir
:ok = BankRouter.dispatch(%OpenAccount{account_number: "ACC123", initial_balance: 1_000})
```

#### Timeouts

A command handler has a default timeout of 5 seconds. The same default as a `GenServer` process call. It must handle the command in this period, otherwise the call fails and the caller exits.

You can configure a different timeout value during command registration or dispatch.

```elixir
defmodule BankRouter do
  use Commanded.Commands.Router

  # configure a timeout of 1 second for the open account command handler
  dispatch OpenAccount, to: OpenAccountHandler, aggregate: BankAccount, identity: :account_number, timeout: 1_000
end
```

```elixir
# dispatch the open account command with a timeout of 2 seconds
:ok = BankRouter.dispatch(%OpenAccount{account_number: "ACC123", initial_balance: 1_000}, timeout: 2_000)
```

#### Multi-command registration

Command routers support multi command registration so you can group related command handlers into the same module.

```elixir
defmodule BankRouter do
  use Commanded.Commands.Router

  dispatch [OpenAccount,CloseAccount], to: BankAccountHandler, aggregate: BankAccount, identity: :account_number
end
```

#### Dispatch returning aggregate version

You can optionally choose to include the aggregate's version as part of the dispatch result by setting the  `include_aggregate_version` option to true:

```elixir
{:ok, aggregate_version} = BankRouter.dispatch(command, include_aggregate_version: true)
```

This is useful when you need to wait for an event handler, such as a read model projection, to be up-to-date before continuing execution or querying its data.

#### Aggregate lifespan

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

  dispatch [OpenAccount,CloseAccount], to: BankAccountHandler, aggregate: BankAccount, lifespan: BankAccountLifespan, identity: :account_number
end
```

The timeout is specified in milliseconds, after which time the aggregate process will be stopped if no other messages are received. You can also return `:hibernate` and the process is hibernated, it will continue its loop once a message is in its message queue. Hibernating an aggregate causes garbage collection and minimises the memory used by the process. Hibernating should not be used aggressively as too much time could be spent garbage collecting.

### Middleware

Allows a command router to define middleware modules that are executed before and after success or failure of each command dispatch.

This provides an extension point to add in command validation, authorization, logging, and other behaviour that you want to be called for every command the router dispatches.

```elixir
defmodule BankingRouter do
  use Commanded.Commands.Router

  middleware CommandLogger
  middleware MyCommandValidator
  middleware AuthorizeCommand

  dispatch OpenAccount, to: OpenAccountHandler, aggregate: BankAccount, identity: :account_number
  dispatch DepositMoney, to: DepositMoneyHandler, aggregate: BankAccount, identity: :account_number
end
```

The middleware modules are executed in the order they’ve been defined. They will receive a `Commanded.Middleware.Pipeline` struct containing the command being dispatched.

#### Example middleware

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

### Events

Domain events indicate that something of importance has occurred, within the context of an aggregate. They are named in the past tense: account registered; funds transferred; fraudulent activity detected.

Create a module per domain event and define the fields with `defstruct`. An event **should contain** a field to uniquely identify the aggregate instance (e.g. `account_number`).

```elixir
defmodule BankAccountOpened do
  defstruct [:account_number, :initial_balance]
end
```

### Event handlers

Use the `Commanded.Event.Handler` macro within your event handler module to implement the defined behaviour. This consists of a single `handle/2` function that receives each published domain event and its metadata, including the event's unique event number. It should return `:ok` on success or `{:error, :reason}` on failure. You can return `{:error, :already_seen_event}` to skip events that have already been handled, due to the at-least-once event delivery of the supported event stores.

Use pattern matching to match on each type of event you are interested in. A catch-all `handle/2` function is included, so all other events will be ignored by default.

```elixir
defmodule AccountBalanceHandler do
  use Commanded.Event.Handler, name: "account_balance"

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
{:ok, _balance} = Agent.start_link(fn -> 0 end, name: AccountBalance)
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

### Process managers

A process manager is responsible for coordinating one or more aggregate roots. It handles events and dispatches commands in response. Process managers have state that can be used to track which aggregate roots are being orchestrated.

Use the `Commanded.ProcessManagers.ProcessManager` macro in your process manager module and implement the three callback functions defined in the behaviour: `interested?/1`, `handle/2`, and `apply/2`.

#### `interested?/1`

The `interested?/1` function is used to indicate which events the process manager receives. The response is used to route the event to an existing instance or start a new process instance.

- Return `{:start, process_uuid}` to create a new instance of the process manager.
- Return `{:continue, process_uuid}` to continue execution of an existing process manager.
- Return `{:stop, process_uuid}` to stop an existing process manager and shutdown its process.
- Return `false` to ignore the event.

#### `handle/2`

A `handle/2` function must exist for each `:start` and `:continue` tagged event previously specified. It receives the process manager's state and the event to be handled. It must return the commands to be dispatched. This may be none, a single command, or many commands.

#### `apply/2`

The `apply/2` function is used to mutate the process manager's state. It receives its current state and the interested event. It must return the modified state.

```elixir
defmodule TransferMoneyProcessManager do
  use Commanded.ProcessManagers.ProcessManager,
    name: "transfer_money_process_manager",
    router: BankRouter

  defstruct [
    transfer_uuid: nil,
    debit_account: nil,
    credit_account: nil,
    amount: nil,
    status: nil
  ]

  def interested?(%MoneyTransferRequested{transfer_uuid: transfer_uuid}), do: {:start, transfer_uuid}
  def interested?(%MoneyWithdrawn{transfer_uuid: transfer_uuid}), do: {:continue, transfer_uuid}
  def interested?(%MoneyDeposited{transfer_uuid: transfer_uuid}), do: {:continue, transfer_uuid}
  def interested?(_event), do: false

  def handle(%TransferMoneyProcessManager{}, %MoneyTransferRequested{transfer_uuid: transfer_uuid, debit_account: debit_account, amount: amount}) do
    %WithdrawMoney{account_number: debit_account, transfer_uuid: transfer_uuid, amount: amount}
  end

  def handle(%TransferMoneyProcessManager{transfer_uuid: transfer_uuid, credit_account: credit_account, amount: amount}, %MoneyWithdrawn{}) do
    %DepositMoney{account_number: credit_account, transfer_uuid: transfer_uuid, amount: amount}
  end

  def handle(%TransferMoneyProcessManager{}, %MoneyDeposited{}), do: []

  ## state mutators

  def apply(%TransferMoneyProcessManager{} = transfer, %MoneyTransferRequested{transfer_uuid: transfer_uuid, debit_account: debit_account, credit_account: credit_account, amount: amount}) do
    %TransferMoneyProcessManager{transfer |
      transfer_uuid: transfer_uuid,
      debit_account: debit_account,
      credit_account: credit_account,
      amount: amount,
      status: :withdraw_money_from_debit_account
    }
  end

  def apply(%TransferMoneyProcessManager{} = transfer, %MoneyWithdrawn{}) do
    %TransferMoneyProcessManager{transfer |
      status: :deposit_money_in_credit_account
    }
  end

  def apply(%TransferMoneyProcessManager{} = transfer, %MoneyDeposited{}) do
    %TransferMoneyProcessManager{transfer |
      status: :transfer_complete
    }
  end
end
```

The name given to the process manager *must* be unique. This is used when subscribing to events from the event store to track the last seen event and ensure they are only received once.

```elixir
{:ok, _} = TransferMoneyProcessManager.start_link(start_from: :current)
```

You can choose to start the process router's event store subscription from the `:origin`, `:current` position or an exact event number using the `start_from` option. The default is to use the origin so it will receive all events. You typically use `:current` when adding a new process manager to an already deployed system containing historical events.

Process manager instance state is persisted to storage after each handled event. This allows the process manager to resume should the host process terminate.

### Supervision

Use a supervisor to host your process managers and event handlers.

```elixir
defmodule Bank.Supervisor do
  use Supervisor

  def start_link do
    Supervisor.start_link(__MODULE__, :ok)
  end

  def init(:ok) do
    children = [
      supervisor(Commanded.Supervisor, []),

      # process manager
      worker(TransferMoneyProcessManager, [start_from: :current], id: :transfer_money_process_manager),

      # event handler
      worker(AccountBalanceHandler, [start_from: :origin], id: :account_balance_handler)
    ]

    supervise(children, strategy: :one_for_one)
  end
end
```

Your application should include the supervisor as a worker.

```elixir
defmodule Bank do
  use Application

  def start(_type, _args) do
    import Supervisor.Spec, warn: false

    children = [
      worker(Bank.Supervisor, [])
    ]

    opts = [strategy: :one_for_one, name: __MODULE__]
    Supervisor.start_link(children, opts)
  end
end
```

### Serialization

JSON serialization is used by default for event and snapshot data.

The included `Commanded.Serialization.JsonSerializer` module provides an extension point to allow additional decoding of the deserialized value. This can be used for parsing data into valid structures, such as date/time parsing from a string.

The example event below has an implementation of the `Commanded.Serialization.JsonDecoder` protocol to parse the date into a `NaiveDateTime` struct.

```elixir
defmodule ExampleEvent do
  defstruct [:name, :date]
end

defimpl Commanded.Serialization.JsonDecoder, for: ExampleEvent do
  @doc """
  Parse the date included in the event
  """
  def decode(%ExampleEvent{date: date} = event) do
    %ExampleEvent{event |
      date: NaiveDateTime.from_iso8601!(date)
    }
  end
end
```

You can implement the `EventStore.Serializer` behaviour to use an alternative serialization format if preferred.

## Read model projections

Your read model can be built using a Commanded event handler and whatever storage provider you prefer.

I typically use Ecto, and a PostgreSQL database, for read model projections. You can use the `project` macro from the [Commanded Ecto projections](https://github.com/slashdotdash/commanded-ecto-projections) library to build projectors, and have the at-least-once event delivery taken care of for you.

## Used in production?

Yes, Commanded is being used in production.

- Case Study: [Building a CQRS/ES web application in Elixir using Phoenix](https://10consulting.com/2017/01/04/building-a-cqrs-web-application-in-elixir-using-phoenix/)

## Event store provider

To use an alternative event store with Commanded you will need to implement the `Commanded.EventStore` behaviour. This defines the contract to be implemented by an adapter module to allow an event store to be used with Commanded. Tests to verify an adapter conforms to the behaviour are provided in `test/event_store_adapter`.

You can use one of the existing adapters ([commanded_eventstore_adapter](https://github.com/slashdotdash/commanded-eventstore-adapter) or [commanded_extreme_adapter](https://github.com/slashdotdash/commanded-extreme-adapter)) to understand what is required.

## Contributing

Pull requests to contribute new or improved features, and extend documentation are most welcome.

Please follow the existing coding conventions, or refer to the [Elixir style guide](https://github.com/niftyn8/elixir_style_guide).

You should include unit tests to cover any changes. Run `mix test` to execute the test suite.

### Contributors

- [Andrey Akulov](https://github.com/astery)
- [Andrzej Sliwa](https://github.com/andrzejsliwa)
- [Brenton Annan](https://github.com/brentonannan)
- [Henry Hazan](https://github.com/henry-hz)

## Need help?

Please [open an issue](https://github.com/slashdotdash/commanded/issues) if you encounter a problem, or need assistance. You can also seek help in the [Gitter chat room](https://gitter.im/commanded/Lobby) for Commanded.

For commercial support, and consultancy, please contact [Ben Smith](mailto:ben@10consulting.com).
