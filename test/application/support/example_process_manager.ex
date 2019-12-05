defmodule Commanded.ExampleProcessManager do
  @moduledoc false

  alias Commanded.ExampleApplication
  alias Commanded.ExampleProcessManager
  alias Commanded.ExampleDomain.BankAccount.Events.BankAccountOpened

  use Commanded.ProcessManagers.ProcessManager,
    application: ExampleApplication,
    name: __MODULE__

  @derive Jason.Encoder
  defstruct [:account_number]

  def interested?(%BankAccountOpened{account_number: account_number}),
    do: {:start, account_number}

  def handle(%ExampleProcessManager{}, %BankAccountOpened{} = event) do
    reply_to = Agent.get(:reply_to, fn reply_to -> reply_to end)

    send(reply_to, {:event, self(), event})

    []
  end

  def apply(%ExampleProcessManager{} = pm, %BankAccountOpened{} = event) do
    %BankAccountOpened{account_number: account_number} = event

    %ExampleProcessManager{pm | account_number: account_number}
  end
end
