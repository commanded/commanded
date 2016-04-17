# Commanded

Command handling middleware for CQRS applications in Elixir.

Designed to be used with [eventstore](https://github.com/slashdotdash/eventstore) and [eventsourced](https://github.com/slashdotdash/eventsourced) libraries as components that comprise a CQRS framework for Elixir.

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

Create a module per command, defining the fields with `defstruct`.

```elixir
defmodule OpenAccount do
  defstruct entity_id: UUID.uuid4, account_number: nil, initial_balance: nil
end
```

Implement the `Commanded.Commands.Handler` behaviour in each of your command handling modules.

```elixir
defmodule OpenAccountHandler do
  @behaviour Commanded.Commands.Handler

  def entity, do: BankAccount

  def handle(%BankAccount{} = state, %OpenAccount{account_number: account_number, initial_balance: initial_balance}) do
    state
    |> BankAccount.open_account(account_number, initial_balance)
  end
end
```

Register the command handler.

```elixir
:ok = Commanded.register(OpenAccount, OpenAccountHandler)
```

Dispatch a command.

```elixir
:ok = Commanded.dispatch(%OpenAccount{account_number: "ACC123", initial_balance: 1_000})
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
