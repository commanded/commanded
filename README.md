# Commanded

Command handling middleware for Command Query Responsibility Segregation (CQRS) applications in Elixir. Use Commanded to build your own applications following the [CQRS/ES](http://cqrs.nu/Faq) architecture.

Provides support for command registration and dispatch; hosting and delegation to aggregate roots; event handling; and long running process managers.

Uses [eventstore](https://github.com/slashdotdash/eventstore) for persistence to PostgreSQL.

MIT License

[![Build Status](https://travis-ci.org/slashdotdash/commanded.svg?branch=master)](https://travis-ci.org/slashdotdash/commanded) [![Join the chat at https://gitter.im/commanded/Lobby](https://badges.gitter.im/commanded/Lobby.svg)](https://gitter.im/commanded/Lobby?utm_source=badge&utm_medium=badge&utm_campaign=pr-badge&utm_content=badge)

---

### Overview

- [Getting started](#getting-started)
- [Aggregate roots](#aggregate-roots)
- [Commands](#commands)
  - [Command handlers](#command-handlers)
  - [Command dispatch and routing](#command-dispatch-and-routing)
- [Middleware](#middleware)
- [Event handlers](#event-handlers)
- [Process managers](#process-managers)
- [Supervision](#supervision)
- [Serialization](#serialization)
- [Contributing](#contributing)

## Getting started

The package can be installed from hex as follows.

  1. Add commanded to your list of dependencies in `mix.exs`:

    ```elixir
    def deps do
      [{:commanded, "~> 0.8"}]
    end
    ```

  2. Ensure commanded is started before your application:

    ```elixir
    def application do
      [applications: [:commanded]]
    end
    ```

  3. Configure the `eventstore` in each environment's mix config file (e.g. `config/dev.exs`), specifying usage of the included JSON serializer:

    ```elixir
    config :eventstore, EventStore.Storage,
      serializer: Commanded.Serialization.JsonSerializer,
      username: "postgres",
      password: "postgres",
      database: "eventstore_dev",
      hostname: "localhost",
      pool_size: 10
    ```

  4. Create the `eventstore` database and tables using the `mix` task.

    ```
    mix event_store.create
    ```

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

It is also possible to route a command directly to an aggregate root. Without requiring an intermediate command handler.

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
:ok = BankRouter.dispatch(%OpenAccount{account_number: "ACC123", initial_balance: 1_000}, 2_000)
```

#### Multi-command registration

Command routers support multi command registration so you can group related command handlers into the same module.

```elixir
defmodule BankRouter do
  use Commanded.Commands.Router

  dispatch [OpenAccount,CloseAccount], to: BankAccountHandler, aggregate: BankAccount, identity: :account_number
end
```

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

### Event handlers

Create an event handler module which implements the `Commanded.Event.Handler` behaviour.

This consists of a single `handle/2` function that receives each published domain event and its metadata, including the event's unique id. It should return `:ok` on success or `{:error, :reason}` on failure.

Use pattern matching to match on each type of event you are interested in. Add a catch-all `handle/2` function for all other events to be ignored.

```elixir
defmodule AccountBalanceHandler do
  @behaviour Commanded.Event.Handler

  def start_link do
    Agent.start_link(fn -> 0 end, name: __MODULE__)
  end

  def handle(%BankAccountOpened{initial_balance: initial_balance}, _metadata) do
    Agent.update(__MODULE__, fn _ -> initial_balance end)
  end

  def handle(%MoneyDeposited{balance: balance}, _metadata) do
    Agent.update(__MODULE__, fn _ -> balance end)
  end

  # ignore all other events
  def handle(_event, _metadata), do: :ok

  def current_balance do
    Agent.get(__MODULE__, fn balance -> balance end)
  end
end
```

Register the event handler with a given name. This is used when subscribing to the event store to track which events the handler has seen during restarts.

```elixir
{:ok, _balance} = AccountBalanceHandler.start_link
{:ok, _handler} = Commanded.Event.Handler.start_link("account_balance", AccountBalanceHandler)
```

You can choose to start the event handler's event store subscription from the `:origin`, `:current` position or an exact event id using the `start_from` option. The default is to use the origin so your handler will receive all events.

```elixir
# start from :origin, :current, or an explicit event id
{:ok, _handler} = Commanded.Event.Handler.start_link("account_balance", AccountBalanceHandler, start_from: :origin)
```

Use the `:current` position when you don't want newly created event handlers to go through all previous events. An example would be adding an event handler to send transactional emails to an already deployed system containing many historical events.

You should use a [supervisor](#supervision) to start your event handlers to ensure they are restarted on error.

### Process managers

A process manager is responsible for coordinating one or more aggregate roots.

It handles events and may dispatch commands in response. Process managers have state that can be used to track which aggregate roots are being orchestrated.

A process manager must implement the `Commanded.ProcessManagers.ProcessManager` behaviour. It defines three callback functions: `interested?/1`, `handle/2`, and `apply/2`.

#### `interested?/1`

The `interested?/1` function is used to indicate which events the process manager receives. The response is used to route the event to an existing instance or start a new process instance.

- Return `{:start, process_uuid}` to create a new instance of the process manager.
- Return `{:continue, process_uuid}` to continue execution of an existing process manager.
- Return `false` to ignore the event.

#### `handle/2`

A `handle/2` function must exist for each interested event previously specified. It receives the process manager's state and the event to be handled. It must return the commands to be dispatched. This may be none, a single command, or many commands.

#### `apply/2`

The `apply/2` function is used to mutate the process manager's state. It receives its current state and the interested event. It must return the modified state.

```elixir
defmodule TransferMoneyProcessManager do
  @behaviour Commanded.ProcessManagers.ProcessManager

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

Register the process manager router with a uniquely identified name. This is used when subscribing to events from the event store to track the last seen event and ensure they are only received once.

```elixir
{:ok, _} = Commanded.ProcessManagers.Router.start_link("transfer_money_process_manager", TransferMoneyProcessManager, start_from: :current)
```

You can choose to start the process router's event store subscription from the `:origin`, `:current` position or an exact event id using the `start_from` option. The default is to use the origin so it will receive all events. You typically use `:current` when adding a new process manager to an already deployed system containing historical events.

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
      worker(Commanded.ProcessManagers.ProcessRouter, ["TransferMoneyProcessManager", TransferMoneyProcessManager, BankRouter, start_from: :current], id: :transfer_money_process_manager),

      # event handler
      worker(Commanded.Event.Handler, ["AccountBalanceHandler", AccountBalanceHandler, start_from: :origin], id: :account_balance_handler)
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

## Contributing

Pull requests to contribute new or improved features, and extend documentation are most welcome.

Please follow the existing coding conventions, or refer to the [Elixir style guide](https://github.com/niftyn8/elixir_style_guide).

You should include unit tests to cover any changes. Run `mix test` to execute the test suite.

### Contributors

- [Andrey Akulov](https://github.com/astery)
- [Andrzej Sliwa](https://github.com/andrzejsliwa)
- [Henry Hazan](https://github.com/henry-hz)
