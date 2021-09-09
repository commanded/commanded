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
