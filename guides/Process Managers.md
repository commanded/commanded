# Process managers

A process manager is responsible for coordinating one or more aggregate roots. It handles events and dispatches commands in response. Process managers have state that can be used to track which aggregate roots are being orchestrated.

Use the `Commanded.ProcessManagers.ProcessManager` macro in your process manager module and implement the three callback functions defined in the behaviour: `interested?/1`, `handle/2`, and `apply/2`.

## `interested?/1`

The `interested?/1` function is used to indicate which events the process manager receives. The response is used to route the event to an existing instance or start a new process instance.

- Return `{:start, process_uuid}` to create a new instance of the process manager.
- Return `{:continue, process_uuid}` to continue execution of an existing process manager.
- Return `{:stop, process_uuid}` to stop an existing process manager and shutdown its process.
- Return `false` to ignore the event.

## `handle/2`

A `handle/2` function must exist for each `:start` and `:continue` tagged event previously specified. It receives the process manager's state and the event to be handled. It must return the commands to be dispatched. This may be none, a single command, or many commands.

## `apply/2`

The `apply/2` function is used to mutate the process manager's state. It receives its current state and the interested event. It must return the modified state.

```elixir
defmodule TransferMoneyProcessManager do
  use Commanded.ProcessManagers.ProcessManager,
    name: "transfer_money_process_manager",
    router: BankRouter

  defstruct [
    transfer_uuid: nil,
    debit_account: nil,
    credit_account: nil,
    amount: nil,
    status: nil
  ]

  def interested?(%MoneyTransferRequested{transfer_uuid: transfer_uuid}), do: {:start, transfer_uuid}
  def interested?(%MoneyWithdrawn{transfer_uuid: transfer_uuid}), do: {:continue, transfer_uuid}
  def interested?(%MoneyDeposited{transfer_uuid: transfer_uuid}), do: {:continue, transfer_uuid}
  def interested?(_event), do: false

  def handle(%TransferMoneyProcessManager{}, %MoneyTransferRequested{transfer_uuid: transfer_uuid, debit_account: debit_account, amount: amount}) do
    %WithdrawMoney{account_number: debit_account, transfer_uuid: transfer_uuid, amount: amount}
  end

  def handle(%TransferMoneyProcessManager{transfer_uuid: transfer_uuid, credit_account: credit_account, amount: amount}, %MoneyWithdrawn{}) do
    %DepositMoney{account_number: credit_account, transfer_uuid: transfer_uuid, amount: amount}
  end

  def handle(%TransferMoneyProcessManager{}, %MoneyDeposited{}), do: []

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

  def apply(%TransferMoneyProcessManager{} = transfer, %MoneyDeposited{}) do
    %TransferMoneyProcessManager{transfer |
      status: :transfer_complete
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
