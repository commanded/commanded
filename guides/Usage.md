# Usage

Commanded provides the building blocks for you to create your own Elixir applications following the CQRS/ES pattern.

A separate guide is provided for each of the components you can build:

- [Aggregate roots](Aggregate%20Roots.md)
- [Commands, registration and dispatch](Commands.md)
- [Events and handlers](Events.md)
- [Process managers](Process%20Managers.md)

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

      def open_account(%BankAccount{account_number: nil} = account, %OpenBankAccount{account_number: account_number, initial_balance: initial_balance})
        when initial_balance > 0
      do
        %BankAccountOpened{account_number: account_number, initial_balance: initial_balance}
      end

      # ensure initial balance is never negative
      def open_account(%BankAccount{} = account, %OpenBankAccount{initial_balance: initial_balance})
        when initial_balance <= 0
      do
        {:error, :initial_balance_must_be_above_zero}
      end

      # ensure account has not already been opened
      def open_account(%BankAccount{account_number: nil} = account, %OpenBankAccount{}) do
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
