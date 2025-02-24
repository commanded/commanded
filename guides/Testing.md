# Testing

When using ES/CQRS, events are first-class citizens. It's critical to be able to assert that specific events are being emitted. Commanded provides test helpers to simplify your life.

## Setting up your test environment / your tests

Please refer to the [Testing your application](https://github.com/commanded/commanded/wiki/Testing-your-application) page on the Wiki for help with configuring your test environment.

### Remember `projection_versions` when truncating tables

If you rely on your read projections in your tests, remember to truncate the `projection_versions` table in your `truncate_readstore_tables/0` function. Otherwise, your projector will ignore everything but the first projection.

```elixir
defp truncate_readstore_tables do
    """
    TRUNCATE TABLE
      table1,
      table2,
      table3,
      projection_versions
    RESTART IDENTITY
    CASCADE;
    """
  end
```

## Asserting that an event is published

Often you'll want to make sure a given event is published. Commanded provides `assert_receive_event/3` and `assert_receive_event/4` functions in the `Commanded.Assertions.EventAssertions` module to help with this.

In the first case, we check that any event is received and use the argument as an assertion.

In the second case, we also provide a predicate function that we can use to narrow our search down to a specific event.

```elixir
import Commanded.Assertions.EventAssertions

test "ensure any event of this type is published" do
  :ok = MyApp.dispatch(%Command{id: 4, date: Date.today})

  assert_receive_event(MyApp, Event, fn event ->
    assert event.id == 4
  end)
end

test "ensure an event is published matching the given predicate" do
  :ok = MyApp.dispatch(%Command{id: 4, date: Date.today})

  assert_receive_event(
    MyApp,
    Event,
    fn event -> event.id == 4 end,
    fn event ->
      assert event.date == Date.today
    end
  )
end
```

## Waiting for an event

Use the `wait_for_event/2` and `wait_for_event/3` functions to pause until a specific type of event, or event type matching a given predicate, is received. This can help you deal with eventual consistency in your tests.

```elixir
import Commanded.Assertions.EventAssertions

test "pause until specific event is published" do
  :ok = BankApp.dispatch(%OpenBankAccount{account_number: "ACC123", initial_balance: 1_000})

  wait_for_event(BankApp, BankAccountOpened, fn opened -> opened.account_number == "ACC123" end)
end
```

## Correlation

It's a given that when going through CQRS, sometimes many events are part of the same action, either because they are returned from the aggregate together, or because event handlers trigger new commands which generate new events, etc. We will usually want to know, for audit trail purposes, that these events belong together.

For this purpose, Commanded provides `assert_correlated/4` which can be used to ensure that specific events have the same `correlation_id`:

```elixir
import Commanded.Assertions.EventAssertions

test "make sure two events are correlated" do
  :ok = BankApp.dispatch(%OpenBankAccount{account_number: "ACC123", initial_balance: 1_000})

  assert_correlated(
    BankApp,
    BankAccountOpened, fn opened -> opened.account_number == "ACC123" end,
    InitialAmountDeposited, fn deposited -> deposited.account_number == "ACC123" end
  )
end
```

## Aggregate state testing

Sometimes it's useful to compare an expected aggregate's state with the previous one. This kind of function should be used
only for testing.

For this purpose, Commanded provides an `aggregate_state` function which returns the current aggregate state.

```elixir
import Commanded.Assertions.EventAssertions

alias Commanded.Aggregates.Aggregate

test "make sure aggregate state are what we wanted" do
  account_number = "ACC123"

  :ok = BankApp.dispatch(%OpenBankAccount{account_number: account_number, initial_balance: 1_000})
  :ok = BankApp.dispatch(%WithdrawnMoney{account_number: account_number, amount: 200})

  wait_for_event(BankApp, BankAccountOpened, fn opened -> opened.account_number == "ACC123" end)
  wait_for_event(BankApp, MoneyWithdrawn, fn withdrawn -> withdrawn.balance == 800 end)

  assert Aggregate.aggregate_state(BankApp, BankAccount, account_number) == %BankAccount{
    account_number: account_number,
    balance: 800,
    state: :active
  }
end
```

## Tests using the event store and read store

To test your application using an event store and read model projection you can take advantage of ExUnit's case template feature to have the databases reset between each test execution. This guarantees that each test starts from a known good state and one test won't affect any other.

First, define a `DataCase` module which is used to reset the event store and read store databases after each test run using the `on_exit/0` callback:

```elixir
# test/support/data_case.ex
defmodule MyApp.DataCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import Commanded.Assertions.EventAssertions
    end
  end

  setup do
    {:ok, _} = Application.ensure_all_started(:my_app)

    on_exit(fn ->
      :ok = Application.stop(:my_app)

      MyApp.Storage.reset!()
    end)

    :ok
  end
end
```

The `DataCase` module uses the following `Storage.reset!/0` function to:

1. Reset the Postgres EventStore database.
2. Truncate the listed tables in the read store database.

Rename `table1`, `table2`, and `table3` to your own table names and remember to include any new tables when added to your app.

```elixir
# test/support/storage.ex
defmodule MyApp.Storage do
  @doc """
  Clear the event store and read store databases
  """
  def reset! do
    reset_eventstore()
    reset_readstore()
  end

  defp reset_eventstore do
    config = MyEventStore.config()

    {:ok, conn} = Postgrex.start_link(config)

    EventStore.Storage.Initializer.reset!(conn, config)
  end

  defp reset_readstore do
    config = Application.get_env(:my_app, MyApp.Repo)

    {:ok, conn} = Postgrex.start_link(config)

    Postgrex.query!(conn, truncate_readstore_tables(), [])
  end

  defp truncate_readstore_tables do
    """
    TRUNCATE TABLE
      table1,
      table2,
      table3
    RESTART IDENTITY
    CASCADE;
    """
  end
end
```

You need to include the `test/support` files in the test environment Elixir paths by adding the following `elixirc_paths/1` function to your app's `mix.exs` file:

```elixir
# mix.exs
defmodule MyApp.Mixfile do
  use Mix.Project

  # Include `test/support` files in test environment
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]
end
```

Finally, you can use the `MyApp.DataCase` case template within any test modules that require access to the databases:

```elixir
# test/example_test.exs
defmodule MyApp.ExampleTest do
  use MyApp.DataCase

  # Each test will be run against clean read and write databases.
  # After test execution (regardless of success or failure) the databases will be reset.
end
```

Run your tests using: `mix test`

When these tests run they will execute against empty event store and read store databases. The caveat with the approach is that the databases will be reset after your tests run; it won't be possible to look at data contained within database after a test fails to debug the failure. The workaround is to temporarily disable the reset operation, run a single failing test, and then you will be able to look at the data. Note that the next time you run any test it will fail because the databases won't have been reset. Subsequent tests will behave normally, assuming you reinstate the reset behaviour.

---

#### Using the in-memory event store for testing

You can use the [[InMemoryEventStore]] to test your application. You can also use an [ExUnit `CaseTemplate` to have the in-memory event store restarted between each test run](https://github.com/commanded/commanded/wiki/In-memory-event-store#exunit-case-template).

---

#### Using `strong` consistency for tests only

You can configure environment specific consistency setting for Commanded event handlers:

```elixir
# config/config.exs
use Mix.Config

config :my_app, consistency: :eventual
```

```elixir
# config/test.exs
use Mix.Config

config :my_app, consistency: :strong
```

Then read the setting when defining your event handlers and process managers:

```elixir
defmodule ExampleEventHandler do
  use Commanded.Event.Handler,
    name: __MODULE__,
    consistency: Application.get_env(:my_app, :consistency, :eventual)
end
```

---

#### Given *events* / When *command* / Then *assert* tests

In your test you can append events to the aggregate's event stream to setup its *given* state. Use `Commanded.EventStore.append_to_stream/4` to append events directly to the event store you've configured to use with Commanded. This allows you to configure a different event store for each environment (e.g. in-memory event store for test env).

You need to map your app's domain events to `Commanded.EventStore.EventData` structs as follows:

```elixir
causation_id = UUID.uuid4()
correlation_id = UUID.uuid4()

event_data =
  Enum.map(events, fn -> event
    %Commanded.EventStore.EventData{
      causation_id: causation_id,
      correlation_id: correlation_id,
      event_type: Commanded.EventStore.TypeProvider.to_string(event),
      data: event,
      metadata: %{},
    }
  )

{:ok, _} = Commanded.EventStore.append_to_stream(application, stream_uuid, expected_version, event_data)
```

The `stream_uuid` will be your aggregate's identity and `expected_version` is the aggregate version (count of events already appended to its stream, use `0` when creating a new aggregate).

Once you've appended the events, you can dispatch the command via your router. The aggregate process will be started, it'll fetch its events, including those you just appended, and then handle the command.
