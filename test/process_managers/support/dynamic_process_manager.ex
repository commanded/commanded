defmodule Commanded.ProcessManagers.DynamicProcessManager do
  @moduledoc false

  alias Commanded.ExampleDomain.BankAccount.Commands.DepositMoney
  alias Commanded.ExampleDomain.BankAccount.Events.{BankAccountOpened, MoneyDeposited}
  alias Commanded.ExampleDomain.BankApp
  alias Commanded.ProcessManagers.DynamicProcessManager
  alias Commanded.UUID

  use Commanded.ProcessManagers.ProcessManager,
    application: BankApp,
    name: __MODULE__

  @derive Jason.Encoder
  defstruct [:account_number]

  def interested?(%BankAccountOpened{account_number: account_number}),
    do: {:start, account_number}

  def interested?(%MoneyDeposited{account_number: account_number}),
    do: {:continue!, account_number}

  def handle(%DynamicProcessManager{}, %BankAccountOpened{} = event) do
    %BankAccountOpened{account_number: account_number} = event

    send_reply(event)

    # Deposit account opening welcome bonus
    [
      %DepositMoney{account_number: account_number, transfer_uuid: UUID.uuid4(), amount: 100}
    ]
  end

  def handle(%DynamicProcessManager{}, %MoneyDeposited{} = event) do
    send_reply(event)

    []
  end

  def apply(%DynamicProcessManager{} = pm, %BankAccountOpened{} = event) do
    %BankAccountOpened{account_number: account_number} = event

    %DynamicProcessManager{pm | account_number: account_number}
  end

  defp send_reply(event) do
    reply_to = Agent.get(:reply_to, fn reply_to -> reply_to end)

    send(reply_to, {:event, self(), event})
  end
end
