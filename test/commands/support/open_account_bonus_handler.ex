defmodule Commanded.Commands.OpenAccountBonusHandler do
  use Commanded.Event.Handler,
    application: Commanded.DefaultApp,
    name: "OpenAccountBonus"

  alias Commanded.ExampleDomain.BankRouter
  alias Commanded.ExampleDomain.BankAccount.Commands.DepositMoney
  alias Commanded.ExampleDomain.BankAccount.Events.BankAccountOpened

  def handle(%BankAccountOpened{} = command, metadata) do
    %BankAccountOpened{account_number: account_number} = command
    %{event_id: causation_id, correlation_id: correlation_id} = metadata

    deposit_welcome_bonus = %DepositMoney{
      account_number: account_number,
      transfer_uuid: UUID.uuid4(),
      amount: 100
    }

    BankRouter.dispatch(deposit_welcome_bonus,
      causation_id: causation_id,
      correlation_id: correlation_id
    )
  end
end
