# Usage

Commanded provides the building blocks for you to create your own Elixir applications following the CQRS/ES pattern.

A separate guide is provided for each of the components you can build:

- Aggregate roots.
- Commands, registration and dispatch.
- Events and handlers.
- Process managers.

Commanded uses strong consistency for command dispatch (write model) and eventual consistency, by default, for the read model. Receiving an `:ok` reply from dispatch indicates the command was successfully handled and any created domain events fully persisted to your chosen event store. You may opt-in to strong consistency for individual event handlers and command dispatch as required.

## Quick overview

Here's an example bank account opening feature built using Commanded to demonstrate its usage.

1. Define an `OpenBankAccount` command:

    ```elixir
    defmodule OpenBankAccount do
      defstruct [:account_number, :initial_balance]
    end
    ```

2. Define a corresponding `BankAccountOpened` domain event:

    ```elixir
    defmodule BankAccountOpened do
      defstruct [:account_number, :initial_balance]
    end
    ```

3. Build a `BankAccount` aggregate root to handle the command, protect its business invariants, and return a domain event when successfully handled:

    ```elixir
    defmodule BankAccount do
      defstruct [account_number: nil, balance: nil]

      # public command API

      # ensure account has not already been opened
      def execute(%BankAccount{account_number: existing_account_number} = account, %OpenBankAccount{}) 
        when not is_nil(existing_account_number)
      do
        {:error, :account_already_opened}
      end

      # ensure initial balance is never negative
      def execute(%BankAccount{} = account, %OpenBankAccount{initial_balance: initial_balance})
        when initial_balance <= 0
      do
        {:error, :initial_balance_must_be_above_zero}
      end

      # ensure a nil account isn't being open
      def execute(%BankAccount{} = account, %OpenBankAccount{account_number: nil})
      do
        {:error, :account_number_cannot_be_nil}
      end

      def execute(%BankAccount{account_number: nil} = account, %OpenBankAccount{account_number: account_number, initial_balance: initial_balance})
      do
        %BankAccountOpened{account_number: account_number, initial_balance: initial_balance}
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

4. Define a router module to route the open account command to the bank account aggregate:

    ```elixir
    defmodule BankRouter do
      use Commanded.Commands.Router

      dispatch OpenBankAccount, to: BankAccount, identity: :account_number
    end
    ```

Finally, we can dispatch a command to open a new bank account:

```elixir
:ok = BankRouter.dispatch(%OpenBankAccount{account_number: "ACC123456", initial_balance: 1_000})
```
