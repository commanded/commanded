# Aggregates

Build your aggregates using standard Elixir modules and functions, with structs to hold state. There is no external dependency requirement.

An aggregate is comprised of its state, public command functions, and state mutators.

## Command functions

A command function receives the aggregate's state and the command to execute. It must return the resultant domain events. This may be none, one, or multiple events.

For business rule violations and errors you may return an `{:error, reason}` tagged tuple or raise an exception.

## State mutators

The state of an aggregate can only be mutated by applying a raised domain event to its state. This is achieved by an `apply/2` function that receives the state and the domain event. It returns the modified state.

Pattern matching is used to invoke the respective `apply/2` function for an event. These functions *must never fail* as they are used when rebuilding the aggregate state from its history of raised domain events. You cannot reject the event once it has occurred.

## Example aggregate

You can write your aggregate with public API functions using the language of your domain.

In this bank account example, the public function to open a new account is `open_account/3`:

```elixir
defmodule BankAccount do
  defstruct [:account_number, :balance]

  # public command API

  def open_account(%BankAccount{account_number: nil}, account_number, initial_balance)
    when initial_balance > 0
  do
    %BankAccountOpened{account_number: account_number, initial_balance: initial_balance}
  end

  def open_account(%BankAccount{}, _account_number, initial_balance)
    when initial_balance <= 0
  do
    {:error, :initial_balance_must_be_above_zero}
  end

  def open_account(%BankAccount{account_number: account_number}, account_number, _initial_balance) do
    {:error, :account_already_opened}
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

An alternative approach is to expose one or more public command functions, `execute/2`, and use pattern matching on the command argument. With this approach you can route your commands directly to the aggregate, without requiring a command handler module.

In this case the example function matches on the `OpenAccount` command module:

```elixir
defmodule BankAccount do
  defstruct [:account_number, :balance]

  # public command API

  def execute(%BankAccount{account_number: nil}, %OpenAccount{account_number: account_number, initial_balance: initial_balance})
    when initial_balance > 0
  do
    %BankAccountOpened{account_number: account_number, initial_balance: initial_balance}
  end

  def execute(%BankAccount{}, %OpenAccount{initial_balance: initial_balance})
    when initial_balance <= 0
  do
    {:error, :initial_balance_must_be_above_zero}
  end

  def execute(%BankAccount{account_number: account_number}, %OpenAccount{account_number: account_number}) do
    {:error, :account_already_opened}
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

## Using `Commanded.Aggregate.Multi` to return multiple events

Sometimes you need to create multiple events from a single command. You can use `Commanded.Aggregate.Multi` to help track the events and update the aggregate state. This can be useful when you want to emit multiple events that depend upon the aggregate state being updated.

Any errors encountered will be returned to the caller, the modified aggregate state and any pending events are discarded.

## Example

In the example below, money is withdrawn from the bank account and the updated balance is used to check whether the account is overdrawn.

```elixir
defmodule BankAccount do
  defstruct [
    account_number: nil,
    balance: 0,
    state: nil,
  ]

  alias Commanded.Aggregate.Multi

  # public command API

  def withdraw(
    %BankAccount{state: :active} = account,
    %WithdrawMoney{amount: amount})
    when is_number(amount) and amount > 0
  do
    account
    |> Multi.new()
    |> Multi.execute(&withdraw_money(&1, amount))
    |> Multi.execute(&check_balance/1)
  end

  # private helpers

  defp withdraw_money(%BankAccount{account_number: account_number, balance: balance}, amount) do
    %MoneyWithdrawn{
      account_number: account_number,
      amount: amount,
      balance: balance - amount
    }
  end

  defp check_balance(%BankAccount{account_number: account_number, balance: balance})
    when balance < 0
  do
    %AccountOverdrawn{account_number: account_number, balance: balance}
  end
  defp check_balance(%BankAccount{}), do: []
end
```

## Aggregate state snapshots

A snapshot represents the aggregate state when all events to that point in time have been replayed. By default snapshotting is disabled for all aggregates.

You can optionally configure state snapshotting for individual aggregates in your app configuration. Instead of loading every event for an aggregate when rebuilding its state, only the snapshot and any events appended since its creation are read.

As an example, assume the snapshot was taken after persisting an event for the aggregate at version 100. When the aggregate process is restarted we load and deserialize the snapshot data as the aggregate's state. Then we fetch and replay the aggregate's events after version 100.

This is a performance optimisation for aggregate's that have a long lifetime or raise a large number of events. It limits the worst case scenario when rebuilding the aggregate state: it will need to read at most this many events.

The following options are configure snapshots for an aggregate:

  - `snapshot_every` - snapshot aggregate state every so many events. Use
    `nil` to disable snapshotting, or exclude the configuration entirely.

  - `snapshot_version` - a non-negative integer indicating the version of
    the aggregate state snapshot. Incrementing this version forces any
    earlier recorded snapshots to be ignored when rebuilding aggregate
    state.

### Example

In `config/config.exs` enable snapshots for `ExampleAggregate` after every ten events:

```elixir
config :commanded, ExampleAggregate
  snapshot_every: 10,
  snapshot_version: 1
```
