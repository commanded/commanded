# Process managers

A process manager is responsible for coordinating one or more aggregates. It handles events and dispatches commands in response. You can think of a process manager as the opposite of an aggregate: aggregates handle commands and create events; process managers handle events and create commands. Process managers have state that can be used to track which aggregates are being orchestrated.

Use the `Commanded.ProcessManagers.ProcessManager` macro in your process manager module and implement the callback functions defined in the behaviour: `interested?/1`, `handle/2`, `apply/2`, and `error/4`.

## `interested?/1`

The `interested?/1` function is used to indicate which events the process manager handles. The response is used to route the event to an existing instance or start a new process instance:

- `{:start, process_uuid}` - create a new instance of the process manager.
- `{:continue, process_uuid}` - continue execution of an existing process manager.
- `{:stop, process_uuid}` - stop an existing process manager, shutdown its process, and delete its persisted state.
- `false` - ignore the event.

## `handle/2`

A `handle/2` function can be defined for each `:start` and `:continue` tagged event previously specified. It receives the process manager's state and the event to be handled. It must return the commands to be dispatched. This may be none, a single command, or many commands.

The `handle/2` function can be omitted if you do not need to dispatch a command and are only mutating the process manager's state.

## `apply/2`

The `apply/2` function is used to mutate the process manager's state. It receives the current state and the domain event, and must return the modified state.

This callback function is optional, the default behaviour is to retain the process manager's current state.

## `error/4`

You can define an `error/4` callback function to handle any errors returned from command dispatch. The function is passed the command dispatch error (e.g. `{:error, :failure}`), the failed command, any pending commands, and a context map containing state passed between retries. Use pattern matching on the error and/or failed command to explicitly handle certain errors or commands.

The `error/4` callback function must return one of the following responses depending upon the severity of error and how you choose to handle it:

- `{:retry, context}` - retry the failed command, provide a context map containing any state passed to subsequent failures. This could be used to count the number of retries, failing after too many attempts.

- `{:retry, delay, context}` - retry the failed command, after sleeping for the requested delay (in milliseconds). Context is a map as described in `{:retry, context}` above.

- `{:skip, :discard_pending}` - discard the failed command and any pending commands.

- `{:skip, :continue_pending}` - skip the failed command, but continue dispatching any pending commands.

- `{:continue, commands, context}` - continue dispatching the given commands. This allows you to retry the failed command, modify it and retry, drop it, or drop all pending commands by passing an empty list `[]`.

- `{:stop, reason}` - stop the process manager with the given reason.

### Error handling example

```elixir
defmodule ExampleProcessManager do
  use Commanded.ProcessManagers.ProcessManager,
    name: "ExampleProcessManager",
    router: ExampleRouter

  # stop process manager after three attempts
  def error({:error, _failure}, _failed_command, _pending_commands, %{attempts: attempts} = context)
    when attempts >= 2
  do
    {:stop, :too_many_attempts}
  end

  # retry command, record attempt count in context map
  def error({:error, _failure}, _failed_command, _pending_commands, context) do
    context = Map.update(context, :attempts, 1, fn attempts -> attempts + 1 end)
    {:retry, context}
  end
end
```

The default behaviour if you don't provide an `error/4` callback is to stop the process manager using the same error reason returned from the failed command dispatch.

You should supervise process managers to ensure they are correctly restarted on error.

## Example process manager

```elixir
defmodule TransferMoneyProcessManager do
  use Commanded.ProcessManagers.ProcessManager,
    name: "TransferMoneyProcessManager",
    router: BankRouter

  defstruct [
    :transfer_uuid,
    :debit_account,
    :credit_account,
    :amount,
    :status
  ]

  def interested?(%MoneyTransferRequested{transfer_uuid: transfer_uuid}), do: {:start, transfer_uuid}
  def interested?(%MoneyWithdrawn{transfer_uuid: transfer_uuid}), do: {:continue, transfer_uuid}
  def interested?(%MoneyDeposited{transfer_uuid: transfer_uuid}), do: {:stop, transfer_uuid}
  def interested?(_event), do: false

  def handle(%TransferMoneyProcessManager{}, %MoneyTransferRequested{transfer_uuid: transfer_uuid, debit_account: debit_account, amount: amount}) do
    %WithdrawMoney{account_number: debit_account, transfer_uuid: transfer_uuid, amount: amount}
  end

  def handle(%TransferMoneyProcessManager{transfer_uuid: transfer_uuid, credit_account: credit_account, amount: amount}, %MoneyWithdrawn{}) do
    %DepositMoney{account_number: credit_account, transfer_uuid: transfer_uuid, amount: amount}
  end

  ## state mutators

  def apply(%TransferMoneyProcessManager{} = transfer, %MoneyTransferRequested{transfer_uuid: transfer_uuid, debit_account: debit_account, credit_account: credit_account, amount: amount}) do
    %TransferMoneyProcessManager{transfer |
      transfer_uuid: transfer_uuid,
      debit_account: debit_account,
      credit_account: credit_account,
      amount: amount,
      status: :withdraw_money_from_debit_account
    }
  end

  def apply(%TransferMoneyProcessManager{} = transfer, %MoneyWithdrawn{}) do
    %TransferMoneyProcessManager{transfer |
      status: :deposit_money_in_credit_account
    }
  end
end
```

The name given to the process manager *must* be unique. This is used when subscribing to events from the event store to track the last seen event and ensure they are only received once.

```elixir
{:ok, _} = TransferMoneyProcessManager.start_link(start_from: :current)
```

You can choose to start the process router's event store subscription from the `:origin`, `:current` position or an exact event number using the `start_from` option. The default is to use the origin so it will receive all events. You typically use `:current` when adding a new process manager to an already deployed system containing historical events.

Process manager instance state is persisted to storage after each handled event. This allows the process manager to resume should the host process terminate.
