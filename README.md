# Commanded

Command handling middleware for CQRS applications in Elixir.

Provides support for command registration and dispatch; hosting and delegation to aggregate roots; event handling; and long running process managers.

Use with [eventstore](https://github.com/slashdotdash/eventstore) and [eventsourced](https://github.com/slashdotdash/eventsourced) as components that comprise a [CQRS](http://cqrs.nu/Faq) framework for Elixir.

MIT License

[![Build Status](https://travis-ci.org/slashdotdash/commanded.svg?branch=master)](https://travis-ci.org/slashdotdash/commanded)

## Getting started

If [available in Hex](https://hex.pm/docs/publish), the package can be installed as:

  1. Add commanded to your list of dependencies in `mix.exs`:

    ```elixir
    def deps do
      [{:commanded, "~> 0.6"}]
    end
    ```

  2. Ensure commanded is started before your application:

    ```elixir
    def application do
      [applications: [:commanded]]
    end
    ```

  3. Configure the `eventstore` in each environment's mix config file (e.g. `config/dev/exs`), specifying usage of the JSON serializer:

    ```elixir
    config :eventstore, EventStore.Storage,
      serializer: Commanded.Serialization.JsonSerializer,
      username: "postgres",
      password: "postgres",
      database: "eventstore_dev",
      hostname: "localhost",
      pool_size: 10,
      extensions: [{Postgrex.Extensions.Calendar, []}]
    ```

  4. Create the `eventstore` database and tables using the `mix` task

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

Use the [eventsourced](https://github.com/slashdotdash/eventsourced) library to build your aggregate roots. This is the expected approach to writing event-sourced domain models.

Follow the convention of returning an `{:ok, aggregate}` tuple on success. For business rule violations and errors you should return an `{:error, reason}` tuple.

```elixir
defmodule BankAccount do
  use EventSourced.AggregateRoot, fields: [account_number: nil, balance: nil]

  # public command API

  def open_account(%BankAccount{} = account, account_number, initial_balance) when initial_balance <= 0 do
    {:error, :initial_balance_must_be_above_zero}
  end

  def open_account(%BankAccount{} = account, account_number, initial_balance) when initial_balance > 0 do
    {:ok, update(account, %BankAccountOpened{account_number: account_number, initial_balance: initial_balance})}
  end

  # state mutators

  def apply(%BankAccount.State{} = state, %BankAccountOpened{} = account_opened) do
    %BankAccount.State{state|
      account_number: account_opened.account_number,
      balance: account_opened.initial_balance
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

It receives the aggregate root and the command to be handled. It must return an `{:ok, aggregate_root}` tuple on success, otherwise an `{:error, reason}` tuple on failure.

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

Create a router to handle registration of each command to its associated handler. Configure each command, mapping it to its handler and aggregate root.

```elixir
defmodule BankRouter do
  use Commanded.Commands.Router

  dispatch OpenAccount, to: OpenAccountHandler, aggregate: BankAccount, identity: :account_number
  dispatch DepositMoney, to: DepositMoneyHandler, aggregate: BankAccount, identity: :account_number
end
```

You can then dispatch a command using the router.

```elixir
:ok = BankRouter.dispatch(%OpenAccount{account_number: "ACC123", initial_balance: 1_000})
```

Command routers support multi command registration so you can group related command handlers into the same module.

```elixir
defmodule BankRouter do
  use Commanded.Commands.Router

  dispatch [OpenAccount,CloseAccount], to: BankAccountHandler, aggregate: BankAccount, identity: :account_number
end
```

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

  def handle(_event, _metadata) do
    # ignore all other events
    :ok
  end

  def current_balance do
    Agent.get(__MODULE__, fn balance -> balance end)
  end
end
```

Register the event handler with a given name. The name is used when subscribing to the event store to record the last seen event.

```elixir
{:ok, _} = AccountBalanceHandler.start_link
{:ok, _} = Commanded.Event.Handler.start_link("account_balance", AccountBalanceHandler)
```

### Process managers

A process manager is responsible for coordinating one or more aggregate roots.

It handles events and may dispatch one or more commands in response. Process managers have state that can be used to track which aggregate roots are being coordinated.

A process manager must implement the `interested?/1` function to indicate which events are used. The response is used to route the event to an existing instance or start a new process.

- Return `{:start, process_uuid}` to create a new instance of the process manager.
- Return `{:continue, process_uuid}` to continue execution of an existing process manager.
- Return `false` to ignore the event

A `handle/2` function must exist for each interested event. It receives the process manager's state and the event to be handled. It must return the state, including any commands that should be dispatched.

Use the `Commanded.ProcessManagers.ProcessManager` macro to define the required state for your process manager. The `dispatch/2` function is used to dispatch a command. This can be called multiple times to dispatch more than one command in response to a received domain event. The process manager's state is updated by calling the `update/2` function. This delegates to an `apply/2` function that mutates the state.

Each process manager `handle/2` function should return an `{:ok, process_manager}` success tuple.

```elixir
defmodule TransferMoneyProcessManager do
  use Commanded.ProcessManagers.ProcessManager, fields: [
    source_account: nil,
    target_account: nil,
    amount: nil,
    status: nil
  ]

  def interested?(%MoneyTransferRequested{transfer_uuid: transfer_uuid}), do: {:start, transfer_uuid}
  def interested?(%MoneyWithdrawn{transfer_uuid: transfer_uuid}), do: {:continue, transfer_uuid}
  def interested?(%MoneyDeposited{transfer_uuid: transfer_uuid}), do: {:continue, transfer_uuid}
  def interested?(_event), do: false

  def handle(%TransferMoneyProcessManager{process_uuid: transfer_uuid} = transfer, %MoneyTransferRequested{source_account: source_account, target_account: target_account, amount: amount} = money_transfer_requested) do
    transfer =
      transfer
      |> dispatch(%WithdrawMoney{account_number: source_account, transfer_uuid: transfer_uuid, amount: amount})
      |> update(money_transfer_requested)

    {:ok, transfer}
  end

  def handle(%TransferMoneyProcessManager{process_uuid: transfer_uuid, state: state} = transfer, %MoneyWithdrawn{} = money_withdrawn) do
    transfer =
      transfer
      |> dispatch(%DepositMoney{account_number: state.target_account, transfer_uuid: transfer_uuid, amount: state.amount})
      |> update(money_withdrawn)

    {:ok, transfer}
  end

  def handle(%TransferMoneyProcessManager{} = transfer, %MoneyDeposited{} = money_deposited) do
    transfer = update(transfer, money_deposited)

    {:ok, transfer}
  end

  ## state mutators

  def apply(%TransferMoneyProcessManager.State{} = transfer, %MoneyTransferRequested{source_account: source_account, target_account: target_account, amount: amount}) do
    %TransferMoneyProcessManager.State{transfer |
      source_account: source_account,
      target_account: target_account,
      amount: amount,
      status: :withdraw_money_from_source_account
    }
  end

  def apply(%TransferMoneyProcessManager.State{} = transfer, %MoneyWithdrawn{}) do
    %TransferMoneyProcessManager.State{transfer |
      status: :deposit_money_in_target_account
    }
  end

  def apply(%TransferMoneyProcessManager.State{} = transfer, %MoneyDeposited{}) do
    %TransferMoneyProcessManager.State{transfer |
      status: :transfer_complete
    }
  end
end

```

Register the process manager router, with a uniquely identified name. This is used when subscribing to events from the event store to track the last seen event and ensure they are only received once.

```elixir
{:ok, _} = Commanded.ProcessManagers.Router.start_link("transfer_money_process_manager", TransferMoneyProcessManager)
```

Process manager instance state is persisted to storage after each handled event. This allows the a process manager to resume should the host process terminate.

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
      worker(Commanded.ProcessManagers.ProcessRouter, ["TransferMoneyProcessManager", TransferMoneyProcessManager, BankRouter], id: :transfer_money_process_manager),

      # event handler
      worker(Commanded.Event.Handler, ["AccountBalanceHandler", AccountBalanceHandler], id: :account_balance_handler)
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

JSON serialization is used by default for event and snapshot data. The included `Commanded.Serialization.JsonSerializer` module provides an extension point to allow additional decoding of the deserialized value. This can be used for parsing data into valid structures, such as date/time parsing from a string.

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

## Contributing

Pull requests to contribute new or improved features, and extend documentation are most welcome.

Please follow the existing coding conventions, or refer to the [Elixir style guide](https://github.com/niftyn8/elixir_style_guide).

You should include unit tests to cover any changes. Run `mix test` to execute the test suite.

### Contributors

- [Andrey Akulov](https://github.com/astery)
- [Andrzej Sliwa](https://github.com/andrzejsliwa)
