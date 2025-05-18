# Aggregates

Build your aggregates using standard Elixir modules and functions, with structs to hold state. There is no external dependency requirement.

An aggregate is comprised of its state, public command functions, and state mutators.

In a CQRS application all state must be derived from the published domain events. This prevents tight coupling between aggregate instances, such as querying for their state, and ensures their state isn't exposed.

If an aggregate needs data owned by another aggregate, then you should lookup the data from a projection and include it in the command before dispatch. Usually this would be a projection into a read model built for querying. You can use Commanded Ecto projections to project events into a SQL database.

## Aggregate state

Use the `defstruct` keyword to define the aggregate state and fields.

```elixir
defmodule ExampleAggregate do
  defstruct [:uuid, :name]
end
```

## Command functions

A command function receives the aggregate's state and the command to execute. It must return the resultant domain events, which may be one event or multiple events. You can return a single event or a list of events: `%Event{}`, `[%Event{}]`, `{:ok, %Event{}}`, or `{:ok, [%Event{}]}`.

To respond without returning an event you can return `:ok`, `nil` or an empty list as either `[]` or `{:ok, []}`.

For business rule violations and errors you may return an `{:error, error}` tagged tuple or raise an exception.

Name your public command functions `execute/2` to dispatch commands directly to the aggregate without requiring an intermediate command handler.

```elixir
defmodule ExampleAggregate do
  def execute(%ExampleAggregate{uuid: nil}, %Create{} = command) do
    %Create{uuid: uuid, name: name} = command

    event = %Created{uuid: uuid, name: name}

    {:ok, event}
  end

  def execute(%ExampleAggregate{}, %Create{}),
    do: {:error, :already_created}
end
```

## State mutators

The state of an aggregate can only be mutated by applying a domain event to its state. This is achieved by an `apply/2` function that receives the state and the domain event. It returns the modified state.

Pattern matching is used to invoke the respective `apply/2` function for an event. These functions **MUST NOT** fail as they are used when rebuilding the aggregate state from its history of domain events. You cannot reject the event once it has occurred.

```elixir
defmodule ExampleAggregate do
  def apply(%ExampleAggregate{}, %Created{} = event) do
    %Created{uuid: uuid, name: name} = event

    %ExampleAggregate{uuid: uuid, name: name}
  end
end
```

## Example aggregate

You can define your aggregate with public API functions using the language of your domain. In this bank account example, the public function to open a new account is `open_account/3`:

```elixir
defmodule BankAccount do
  defstruct [:account_number, :balance]

  # Public API

  def open_account(%BankAccount{account_number: nil}, account_number, initial_balance)
    when initial_balance > 0
  do
    event = %BankAccountOpened{account_number: account_number, initial_balance: initial_balance}

    {:ok, event}
  end

  def open_account(%BankAccount{}, _account_number, initial_balance)
    when initial_balance <= 0
  do
    {:error, :initial_balance_must_be_above_zero}
  end

  def open_account(%BankAccount{}, _account_number, _initial_balance) do
    {:error, :account_already_opened}
  end

  # State mutators

  def apply(%BankAccount{} = account, %BankAccountOpened{} = event) do
    %BankAccountOpened{account_number: account_number, initial_balance: initial_balance} = event

    %BankAccount{account |
      account_number: account_number,
      balance: initial_balance
    }
  end
end
```

With this approach you must dispatch the command to a command handler:

```elixir
defmodule Commanded.ExampleDomain.OpenAccountHandler do
  alias BankAccount
  alias Commands.OpenAccount

  @behaviour Commanded.Commands.Handler

  def handle(%BankAccount{} = aggregate, %OpenAccount{} = command) do
    %OpenAccount{account_number: account_number, initial_balance: initial_balance} = command

    BankAccount.open_account(aggregate, account_number, initial_balance)
  end
end
```

An alternative approach is to expose one or more public command functions, `execute/2`, and use pattern matching on the command argument. With this approach you can route your commands directly to the aggregate. To make this more explicit, you can implement the `Commanded.Aggregates.Aggregate` behaviour.

In this example the `execute/2` function pattern matches on the `OpenAccount` command module:

```elixir
defmodule BankAccount do
  defstruct [:account_number, :balance]

  alias Commanded.Aggregates.Aggregate
  @behaviour Aggregate

  # Public API

  @impl Aggregate
  def execute(
    %BankAccount{account_number: nil},
    %OpenAccount{initial_balance: initial_balance} = command
    ) when initial_balance > 0
  do
    %OpenAccount{account_number: account_number} = command

    %BankAccountOpened{account_number: account_number, initial_balance: initial_balance}
  end

  @impl Aggregate
  def execute(%BankAccount{}, %OpenAccount{initial_balance: initial_balance})
    when initial_balance <= 0
  do
    {:error, :initial_balance_must_be_above_zero}
  end

  @impl Aggregate
  def execute(%BankAccount{}, %OpenAccount{}) do
    {:error, :account_already_opened}
  end

  # State mutators

  @impl Aggregate
  def apply(%BankAccount{} = account, %BankAccountOpened{} = event) do
    %BankAccountOpened{account_number: account_number, initial_balance: initial_balance} = event

    %BankAccount{account |
      account_number: account_number,
      balance: initial_balance
    }
  end
end
```

> #### Effective Aggregate State {: .tip}
>
> The aggregate state should be carefully designed to maintain only the data required to:
>
> - Enforce business rules and invariants (e.g. preventing withdrawals that would overdraw an account)
> - Provide context for command handling based on previous events (e.g. checking an order's current status)
> - Make decisions that depend on historical events (e.g. verifying a refund doesn't exceed original payment)
>
> A common anti-pattern is blindly copying all event data into aggregate state without considering whether that data
> is actually needed for command handling. If a piece of state is never referenced in any command handling logic,
> it should be removed from the aggregate. This keeps the aggregate focused and maintainable.
>
> State that is only needed for querying/reporting should be maintained in read models rather than aggregate state.

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

  alias Commanded.Aggregate
  alias Commanded.Aggregate.Multi

  @behaviour Aggregate

  # Public API

  @impl Aggregate
  def execute(
    %BankAccount{state: :active} = account,
    %WithdrawMoney{amount: amount})
    when is_number(amount) and amount > 0
  do
    account
    |> Multi.new()
    |> Multi.execute(&withdraw_money(&1, amount))
    |> Multi.execute(&check_balance/1)
  end

  # State mutators

  @impl Aggregate
  def apply(%BankAccount{} = state, %MoneyWithdrawn{balance: balance}),
    do: %BankAccount{state | balance: balance}

  def apply(%BankAccount{} = state, %AccountOverdrawn{}),
    do: %BankAccount{state | state: :overdrawn}

  # Private helpers

  defp withdraw_money(%BankAccount{} = account, amount) do
    %BankAccount{account_number: account_number, balance: balance} = account

    event = %MoneyWithdrawn{
      account_number: account_number,
      amount: amount,
      balance: balance - amount
    }

    {:ok, event}
  end

  defp check_balance(%BankAccount{balance: balance} = account)
    when balance < 0
  do
    %BankAccount{account_number: account_number} = account

    event = %AccountOverdrawn{account_number: account_number, balance: balance}

    {:ok, event}
  end

  defp check_balance(%BankAccount{}), do: :ok
end
```

## Aggregate state snapshots

A snapshot represents the aggregate state when all events to that point in time have been replayed. You can optionally configure state snapshotting for individual aggregates in your app configuration. Instead of loading every event for an aggregate when rebuilding its state, only the snapshot and any events appended since its creation are read. By default snapshotting is disabled for all aggregates.

As an example, assume a snapshot was taken after persisting an event for the aggregate at version 100. When the aggregate process is restarted we load and deserialize the snapshot data as the aggregate's initial state. Then we fetch and replay the aggregate's events after version 100.

This is a performance optimisation for aggregates that have a long lifetime or raise a large number of events. It limits the worst case scenario when rebuilding the aggregate state: it will need to read the snapshot and at most this many events from storage.

Use the following options to configure snapshots for an aggregate:

- `snapshot_every` - snapshot aggregate state every so many events. Use `nil` to disable snapshotting, or exclude the configuration entirely.

- `snapshot_version` - a non-negative integer indicating the version of the aggregate state snapshot. Incrementing this version forces any earlier recorded snapshots to be ignored when rebuilding aggregate state.

### Example

In `config/config.exs` enable snapshots for `ExampleAggregate` after every ten events:

```elixir
config :my_app, MyApp.Application,
  snapshotting: %{
    MyApp.ExampleAggregate => [
      snapshot_every: 10,
      snapshot_version: 1
    ]
  }
```

### Snapshot serialization

Aggregate state will be serialized using the configured event store serializer, by default this stores the data as JSON. Remember to derive the `Jason.Encoder` protocol for the aggregate state to ensure JSON serialization is supported, as shown below.

```elixir
defmodule ExampleAggregate do
  @derive Jason.Encoder
  defstruct [:name, :datetime]
end
```

You can use the `Commanded.Serialization.JsonDecoder` protocol to decode the parsed JSON data into the expected types:

```elixir
defimpl Commanded.Serialization.JsonDecoder, for: ExampleAggregate do
  @doc """
  Parse the datetime included in the aggregate state
  """
  def decode(%ExampleAggregate{} = state) do
    %ExampleAggregate{datetime: datetime} = state

    {:ok, dt, _} = DateTime.from_iso8601(datetime)

    %ExampleAggregate{state | datetime: dt}
  end
end
```

Note: The default JSON encoding of a `DateTime` struct uses the `to_iso8601/1` function which is why we must decode it using the `from_iso8601/1` function.

### Rebuilding an aggregate snapshot

Whenever you change the structure of an aggregate's state you **MUST** increment the `snapshot_version` number. The aggregate state will be rebuilt from its events, ignoring any existing snapshots. They will be overwritten when the next snapshot is taken.
