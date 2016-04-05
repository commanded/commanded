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
defmodule Commanded.ExampleDomain.BankAccount do
  defmodule Commands do
    defmodule OpenAccount do
      defstruct entity_id: UUID.uuid4, account_number: nil, initial_balance: nil
    end
  end
end
```

Implement the `Commanded.Commands.Handler` behaviour in each of your command handling modules.

```elixir
defmodule OpenAccountHandler do
  @behaviour Commanded.Commands.Handler

  def entity, do: BankAccount

  def handle(state = %BankAccount{}, %OpenAccount{account_number: account_number, initial_balance: initial_balance}) do
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
