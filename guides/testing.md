# Testing

When using ES/CQRS, events are first-class citizens. It's critical to be able to assert that specific events are being emitted. Commanded provides test helpers to simplify your life.

## Setting up your test environment / your tests

There's a page on the Wiki that will help you configure your environment:

https://github.com/commanded/commanded/wiki/Testing-your-application

## Asserting that an event is published

Often you'll want to make sure a given event is published. Commanded provides `assert_receive_event/2` and `assert_receive_event/3` to help with this.

In the first case, we check that any event is received and use the argument as an assertion.

In the second case, we also provide a predicate function that we can use to narrow our search down to a specific event.

```elixir
import Commanded.Assertions.EventAssertions

test "ensure any event of this type is published" do
  Router.dispatch(Command.new(%{id: 4, date: Date.today}, consistency: eventual)
  assert_receive_event(Event, fn(event) -> assert event.id == 4 end)
  # do something after event has been published
end

test "pause until specific event is published" do
  Router.dispatch(Command.new(%{id: 4, date: Date.today}), consistency: eventual)
  assert_receive_event(
    Event,
    fn(event) -> event.id == 4 end,
    fn(event) -> assert event.date == Date.today end
  )
  # do something after event has been published
end

```

## Correlation

It's a given that when going through CQRS, sometimes many events are part of the same action, either because they are returned from the aggregate together, or because event handlers trigger new commands which generate new events, etc. We will usually want to know, for audit trail purposes, that these events belong together.

For this purpose, commanded provides `assert_correlated/4`.

We find specific events and make sure they have the same `correlation_id` (read about those [here](./Commands.md#correlation-and-causation-ids)).

```elixir
import Commanded.Assertions.EventAssertions

test "make sure two events are correlated" do
  Router.dispatch(OpenBankAccount.new(%{id: 4, initial_amount: 200}))
  assert_correlated(
    BankAccountOpened, fn opened -> opened.account_id == 4 end,
    InitialAmountDeposited, fn deposited -> deposited.account_id == 4 end
  )

end
```

## Handling eventual consistency

Sometimes you don't need to create strong consistency, and you don't want to surface through your API the ability to choose the consistency. In this case, commanded provides `wait_for_event/1` and `wait_for_event/2` :

```elixir
import Commanded.Assertions.EventAssertions

test "pause until any event of this type is published" do
  Router.dispatch(Command.new(%{id: 4, date: Date.today}), consistency: eventual)
  wait_for_event(Event)
  # do something after event has been published
end

test "pause until specific event is published" do
  Router.dispatch(Command.new(%{id: 4, date: Date.Today}), consistency: eventual)
  wait_for_event(Event, fn(event) -> event.id == 4 end)
  # do something after event has been published
end

```
