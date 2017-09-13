# Aggregate roots

Build your aggregate roots using standard Elixir modules and functions, with structs to hold state. There is no external dependency requirement.

An aggregate root is comprised of its state, public command functions, and state mutators.

## Command functions

A command function receives the aggregate root's state and the command to execute. It must return the resultant domain events. This may be none, one, or multiple events.

For business rule violations and errors you may return an `{:error, reason}` tagged tuple or raise an exception.

## State mutators

The state of an aggregate root can only be mutated by applying a raised domain event to its state. This is achieved by an `apply/2` function that receives the state and the domain event. It returns the modified state.

Pattern matching is used to invoke the respective `apply/2` function for an event. These functions *must never fail* as they are used when rebuilding the aggregate state from its history of raised domain events. You cannot reject the event once it has occurred.

## Example aggregate root

```elixir
defmodule BankAccount do
  defstruct [account_number: nil, balance: nil]

  # public command API

  def open_account(%BankAccount{} = account, account_number, initial_balance)
    when initial_balance > 0
  do
    %BankAccountOpened{account_number: account_number, initial_balance: initial_balance}
  end

  def open_account(%BankAccount{} = account, account_number, initial_balance)
    when initial_balance <= 0
  do
    {:error, :initial_balance_must_be_above_zero}
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
