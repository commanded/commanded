# Commanded

Command handling middleware for CQRS applications in Elixir.

Use with [eventstore](https://github.com/slashdotdash/eventstore) and [eventsourced](https://github.com/slashdotdash/eventsourced) as components that comprise a [CQRS](http://cqrs.nu/Faq) framework for Elixir.

MIT License

[![Build Status](https://travis-ci.org/slashdotdash/commanded.svg?branch=master)](https://travis-ci.org/slashdotdash/commanded)

## Getting started

If [available in Hex](https://hex.pm/docs/publish), the package can be installed as:

  1. Add commanded to your list of dependencies in `mix.exs`:

    ```elixir
    def deps do
      [{:commanded, "~> 0.0.1"}]
    end
    ```

  2. Ensure commanded is started before your application:

    ```elixir
    def application do
      [applications: [:commanded]]
    end
    ```

## Sample usage

Start the top level Supervisor process.

```elixir
{:ok, _} = Commanded.Supervisor.start_link
```

### Command handlers

Create a module per command, defining the fields with `defstruct`. A command must contain a field to uniquely identify the aggregate instance (e.g. `account_number`).

```elixir
defmodule OpenAccount do
  defstruct [:account_number, :initial_balance]
end
```

Implement the `Commanded.Commands.Handler` behaviour consisting of a single `handle/2` function. It receives the aggregate root and the  command to be handled. It must return the aggregate root.

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
defmodule BankingRouter do
  use Commanded.Commands.Router

  dispatch OpenAccount, to: OpenAccountHandler, aggregate: BankAccount, identity: :account_number
  dispatch DepositMoney, to: DepositMoneyHandler, aggregate: BankAccount, identity: :account_number
end
```

You can then dispatch a command using the router.

```elixir
:ok = BankingRouter.dispatch(%OpenAccount{account_number: "ACC123", initial_balance: 1_000})
```

### Event handlers

Create an event handler module which implements `handle/1` for each event you are interested in.

Add a catch-all `handle/1` function for all other events to ignore.

```elixir
defmodule AccountBalanceHandler do
  def start_link do
    Agent.start_link(fn -> 0 end, name: __MODULE__)
  end

  def handle(%BankAccountOpened{initial_balance: initial_balance}) do
    Agent.update(__MODULE__, fn _ -> initial_balance end)
  end

  def handle(%MoneyDeposited{balance: balance}) do
    Agent.update(__MODULE__, fn _ -> balance end)
  end

  def handle(_) do
    # ignore all other events
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

A process manager is responsible for communicating between one or more aggregate roots.

It handles events and dispatches commands in response. Process managers have state that can be used to track which aggregate roots are being coordinated.

A process manager must implement `interested?/1` to indicate which events are used, and to route the event to an existing instance or start a new process. A `handle/2` function must exist for each interested event. It receives the process manager's state and the event to be handled. It must return the state, including any commands that should be dispatched.

```elixir
defmodule TransferMoneyProcessManager do
  defstruct commands: [], transfer_uuid: nil, source_account: nil, target_account: nil, amount: nil, status: nil

  def interested?(%MoneyTransferRequested{transfer_uuid: transfer_uuid}), do: {:start, transfer_uuid}
  def interested?(%MoneyWithdrawn{transfer_uuid: transfer_uuid}), do: {:continue, transfer_uuid}
  def interested?(%MoneyDeposited{transfer_uuid: transfer_uuid}), do: {:continue, transfer_uuid}
  def interested?(_event), do: false

  def new(process_uuid) do
    %TransferMoneyProcessManager{transfer_uuid: process_uuid}
  end

  def handle(%TransferMoneyProcessManager{transfer_uuid: transfer_uuid} = transfer, %MoneyTransferRequested{source_account: source_account, target_account: target_account, amount: amount}) do
    transfer =
      transfer
      |> dispatch(%WithdrawMoney{account_number: source_account, transfer_uuid: transfer_uuid, amount: amount})

    %TransferMoneyProcessManager{transfer |
      source_account: source_account,
      target_account: target_account,
      amount: amount,
      status: :withdraw_money_from_source_account
    }
  end

  def handle(%TransferMoneyProcessManager{transfer_uuid: transfer_uuid} = transfer, %MoneyWithdrawn{} = _money_withdrawn) do
    transfer =
      transfer
      |> dispatch(%DepositMoney{account_number: transfer.target_account, transfer_uuid: transfer_uuid, amount: transfer.amount})

    %TransferMoneyProcessManager{transfer |
      status: :deposit_money_in_target_account
    }
  end

  def handle(%TransferMoneyProcessManager{} = transfer, %MoneyDeposited{} = _money_deposited) do
    %TransferMoneyProcessManager{transfer |
      status: :transfer_complete
    }
  end

  def handle(_transfer, _event) do
      # ignore any other events
  end

  defp dispatch(%TransferMoneyProcessManager{commands: commands} = transfer, command) do
    %TransferMoneyProcessManager{transfer |
      commands: [command | commands]
    }
  end
end
```

Register the process manager router, with a uniquely identified name. This is used when subscribing to events from the event store to track the last seen event and ensure they are only received once.

```elixir
{:ok, _} = Commanded.ProcessManagers.Router.start_link("transfer_money_process_manager", TransferMoneyProcessManager)
```
