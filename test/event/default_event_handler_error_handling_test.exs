defmodule Commanded.Event.DefaultEventHandlerErrorHandlingTest do
  use Commanded.StorageCase

  alias Commanded.Event.DefaultErrorEventHandler
  alias Commanded.ExampleDomain.BankAccount.Commands.OpenAccount
  alias Commanded.ExampleDomain.BankRouter
  alias Commanded.Helpers.{CommandAuditMiddleware, ProcessHelper}

  setup do
    {:ok, pid} = CommandAuditMiddleware.start_link()

    on_exit fn ->
      ProcessHelper.shutdown(pid)
    end

    :ok
  end

  test "should stop event handler on error" do
    account_number = UUID.uuid4()

    {:ok, handler} = DefaultErrorEventHandler.start_link()

    Process.unlink(handler)
    ref = Process.monitor(handler)

    :ok = BankRouter.dispatch(%OpenAccount{account_number: account_number, initial_balance: 1_000})

    assert_receive {:DOWN, ^ref, _, _, _}
    refute Process.alive?(handler)
  end
end
