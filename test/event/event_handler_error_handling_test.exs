defmodule Commanded.Event.EventHandlerErrorHandlingTest do
  use Commanded.StorageCase

  defmodule ErrorEventHandler do
    use Commanded.Event.Handler, name: "ErrorEventHandler"

    alias Commanded.ExampleDomain.BankAccount.Events.BankAccountOpened

    def handle(%BankAccountOpened{}, _metadata), do: {:error, :failed}
  end

  alias Commanded.ExampleDomain.BankAccount.Commands.OpenAccount
  alias Commanded.ExampleDomain.BankAccount.Events.BankAccountOpened
  alias Commanded.ExampleDomain.BankRouter
  alias Commanded.Helpers.CommandAuditMiddleware

  setup do
    CommandAuditMiddleware.start_link()
    :ok
  end

  test "should stop event handler on error" do
    account_number = UUID.uuid4()

    {:ok, handler} = ErrorEventHandler.start_link()

    Process.unlink(handler)
    ref = Process.monitor(handler)

    :ok = BankRouter.dispatch(%OpenAccount{account_number: account_number, initial_balance: 1_000})

    assert_receive {:DOWN, ^ref, _, _, _}
    refute Process.alive?(handler)
  end
end
