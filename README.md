# Commanded

Command handling middleware for CQRS applications in Elixir.

Designed to be used with [eventstore](https://github.com/slashdotdash/eventstore) and [eventsourced](https://github.com/slashdotdash/eventsourced) libraries as components that comprise a CQRS framework for Elixir.

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

### Command handlers

Implement the `Commanded.Commands.Handler` behaviour in each of your command handler modules.

```elixir
defmodule OpenAccountHandler do
  @behaviour Commanded.Commands.Handler

  def aggregate, do: BankAccount

  def handle(state = %BankAccount{}, %OpenAccount{account_number: account_number, initial_balance: initial_balance}) do
    state
    |> BankAccount.open_account(account_number, initial_balance)
  end
end
```

Register the handler with the command registry.

```elixir
{:ok, command_registry} = Commanded.Commands.Registry.start_link

:ok = Registry.register(OpenAccount, OpenAccountHandler)
```
