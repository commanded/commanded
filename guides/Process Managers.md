# Process managers

A process manager is responsible for coordinating one or more aggregates. It handles events and dispatches commands in response. You can think of a process manager as the opposite of an aggregate: aggregates handle commands and create events; process managers handle events and create commands. Process managers have state that can be used to track which aggregates are being orchestrated.

Use the `Commanded.ProcessManagers.ProcessManager` macro in your process manager module and implement the callback functions defined in the behaviour: `c:Commanded.ProcessManagers.ProcessManager.interested?/1`, `c:Commanded.ProcessManagers.ProcessManager.handle/2`, `c:Commanded.ProcessManagers.ProcessManager.apply/2`, and `c:Commanded.ProcessManagers.ProcessManager.error/3`.

## `interested?/1`

The `c:Commanded.ProcessManagers.ProcessManager.interested?/1` function is used to indicate which events the process manager handles. The response is used to route the event to an existing instance or start a new process instance:

- `{:start, process_uuid}` - create a new instance of the process manager.
- `{:start!, process_uuid}` - create a new instance of the process manager (strict).
- `{:continue, process_uuid}` - continue execution of an existing process manager.
- `{:continue!, process_uuid}` - continue execution of an existing process manager (strict).
- `{:stop, process_uuid}` - stop an existing process manager, shutdown its
  process, and delete its persisted state.
- `false` - ignore the event.

You can return a list of process identifiers when a single domain event is to be handled by multiple process instances.

### Strict process routing

Using strict routing, with `:start!` or `:continue!`, enforces the following validation checks:

- `{:start!, process_uuid}` - validate process does not already exist.
- `{:continue!, process_uuid}` - validate process already exists.

If the check fails an error will be passed to the `error/3` callback function:

- `{:error, {:start!, :process_already_started}}`
- `{:error, {:continue!, :process_not_started}}`

The `c:Commanded.ProcessManagers.ProcessManager.error/3` function can choose to `:stop` the process or `:skip` the problematic event.

## `handle/2`

A `handle/2` function can be defined for each `:start` and `:continue` tagged event previously specified. It receives the process manager's state and the event to be handled. It must return the commands to be dispatched. This may be none, a single command, or many commands.

The `handle/2` function can be omitted if you do not need to dispatch a command and are only mutating the process manager's state.

## `apply/2`

The `c:Commanded.ProcessManagers.ProcessManager.apply/2` function is used to mutate the process manager's state. It receives the current state and the domain event, and must return the modified state.

This callback function is optional, the default behaviour is to retain the process manager's current state.

## `error/3`

You can define an `c:Commanded.ProcessManagers.ProcessManager.error/3` callback function to handle any errors or exceptions during event handling or returned by commands dispatched from your process manager. The function is passed the error (e.g. `{:error, :failure}`), the failed event or command, and a failure context. See `Commanded.ProcessManagers.FailureContext` for details.

Use pattern matching on the error and/or failed event/command to explicitly handle certain errors, events, or commands. You can choose to retry, skip, ignore, or stop the process manager after a command dispatch error.

The default behaviour, if you don't provide an `c:Commanded.ProcessManagers.ProcessManager.error/3` callback, is to stop the process manager using the exact error reason returned from the event handler function or command dispatch.

The `c:Commanded.ProcessManagers.ProcessManager.error/3` callback function must return one of the following responses depending upon the severity of error and how you choose to handle it:

- `{:retry, context}` - retry the failed command, provide a context map containing any state passed to subsequent failures. This could be used to count the number of retries, failing after too many attempts.

- `{:retry, delay, context}` - retry the failed command, after sleeping for the requested delay (in milliseconds). Context is a map as described in `{:retry, context}` above.

- `{:stop, reason}` - stop the process manager with the given reason.

For event handling failures, when failure source is an event, you can also return:

- `:skip` - to skip the problematic event. No commands will be dispatched.

For command dispatch failures, when failure source is a command, you can also return:

- `{:continue, commands, context}` - continue dispatching the given commands. This allows you to retry the failed command, modify it and retry, drop it, or drop all pending commands by passing an empty list `[]`.

- `{:skip, :discard_pending}` - discard the failed command and any pending commands.

- `{:skip, :continue_pending}` - skip the failed command, but continue dispatching any pending commands.

## Supervision

Supervise your process managers to ensure they are restarted on error.

```elixir
defmodule Bank.Payments.Supervisor do
  use Supervisor

  def start_link(_arg) do
    Supervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init(_arg) do
    Supervisor.init(
      [
        Bank.Payments.TransferMoneyProcessManager
      ],
      strategy: :one_for_one
    )
  end
end
```

### Supervision caveats

The default error handling strategy is to stop the process manager. When supervised, the process will be restarted and will attempt to handle the same event again, which will likely result in the same error. This could lead to too many restarts of the supervisor, which may eventually cause the application to stop, depending upon your supervision tree and its strategy.

To prevent this you can choose to define the default error handling strategy as `:skip` to skip over any problematic events.

```elixir
defmodule ExampleProcessManager do
  use Commanded.ProcessManagers.ProcessManager,
    application: ExampleApp,
    name: __MODULE__

  require Logger

  # By default skip any problematic events
  def error(error, _command_or_event, _failure_context) do
    Logger.error(fn -> "#{__MODULE__} encountered an error: " <> inspect(error) end)

    :skip
  end
end
```

Alternatively you can define the restart strategy of your process manager as `:temporary` to prevent it from being restarted on termination. This approach will require manual intervention to fix the stopped process manager, but ensures that it won't miss any events nor crash the application.

### Error handling example

Define an `error/3` callback function to determine how to handle errors during event handling and command dispatch.

```elixir
defmodule ExampleProcessManager do
  use Commanded.ProcessManagers.ProcessManager,
    application: ExampleApp,
    name: "ExampleProcessManager"

  # Stop process manager after three failures
  def error({:error, _failure}, _failed_message, %{context: %{failures: failures}})
    when failures >= 2
  do
    {:stop, :too_many_failures}
  end

  # Retry command, record failure count in context map
  def error({:error, _failure}, _failed_message, %{context: context}) do
    context = Map.update(context, :failures, 1, fn failures -> failures + 1 end)
    {:retry, context}
  end
end
```

The default behaviour if you don't provide an `error/3` callback is to stop the process manager using the same error reason returned from the failed command dispatch.

## Example process manager

```elixir
defmodule TransferMoneyProcessManager do
  use Commanded.ProcessManagers.ProcessManager,
    application: ExampleApp,
    name: "TransferMoneyProcessManager"

  @derive Jason.Encoder
  defstruct [
    :transfer_uuid,
    :debit_account,
    :credit_account,
    :amount,
    :status
  ]

  # Process routing

  def interested?(%MoneyTransferRequested{transfer_uuid: transfer_uuid}), do: {:start, transfer_uuid}
  def interested?(%MoneyWithdrawn{transfer_uuid: transfer_uuid}), do: {:continue, transfer_uuid}
  def interested?(%MoneyDeposited{transfer_uuid: transfer_uuid}), do: {:stop, transfer_uuid}
  def interested?(_event), do: false

  # Command dispatch

  def handle(%TransferMoneyProcessManager{}, %MoneyTransferRequested{} = event) do
    %MoneyTransferRequested{transfer_uuid: transfer_uuid, debit_account: debit_account, amount: amount} = event

    %WithdrawMoney{account_number: debit_account, transfer_uuid: transfer_uuid, amount: amount}
  end

  def handle(%TransferMoneyProcessManager{} = pm, %MoneyWithdrawn{}) do
    %TransferMoneyProcessManager{transfer_uuid: transfer_uuid, credit_account: credit_account, amount: amount} = pm

    %DepositMoney{account_number: credit_account, transfer_uuid: transfer_uuid, amount: amount}
  end

  # State mutators

  def apply(%TransferMoneyProcessManager{} = transfer, %MoneyTransferRequested{} = event) do
    %MoneyTransferRequested{transfer_uuid: transfer_uuid, debit_account: debit_account, credit_account: credit_account, amount: amount} = event

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
{:ok, _pid} = TransferMoneyProcessManager.start_link(start_from: :current)
```

You can choose to start the process router's event store subscription from the `:origin`, `:current` position or an exact event number using the `start_from` option. The default is to use `:origin` so it will receive all events. You typically use `:current` when adding a new process manager to an already deployed system containing historical events.

Process manager instance state is persisted to storage after each handled event. This allows the process manager to resume should the host process terminate.

## Configuration options

- `consistency` - defined as one of either `:strong` or `:eventual` (default) for event handling.
- `event_timeout` - a timeout for event handling to ensure that events are processed in a timely manner without getting stuck.
- `idle_timeout` - to reduce memory usage you can configure an idle timeout, in milliseconds, after which an inactive process instance will be shutdown.

Refer to the `Commanded.ProcessManagers.ProcessManager` module docs for more details.
