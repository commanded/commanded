defmodule Commanded.ProcessManager.DynamicProcessManagerApplicationTest do
  use ExUnit.Case

  alias Commanded.ExampleDomain.BankAccount.Commands.OpenAccount
  alias Commanded.ExampleDomain.BankAccount.Events.{BankAccountOpened, MoneyDeposited}
  alias Commanded.ExampleDomain.BankApp
  alias Commanded.Helpers.{CommandAuditMiddleware, Wait}
  alias Commanded.ProcessManagers.{DynamicProcessManager, ProcessRouter}
  alias Commanded.UUID

  setup_all do
    start_supervised!(CommandAuditMiddleware)
    :ok
  end

  describe "dynamic application process manager" do
    setup do
      start_reply_to_agent!()
      start_supervised!({BankApp, name: :example1})
      start_supervised!({BankApp, name: :example2})
      :ok
    end

    test "should only receive events from named application" do
      pid1 = start_supervised!({DynamicProcessManager, application: :example1})
      pid2 = start_supervised!({DynamicProcessManager, application: :example2})

      {:ok, account_number} = open_account(:example1)

      instance1 = wait_for_process_instance(pid1, account_number)

      assert_receive {:event, ^instance1, %BankAccountOpened{account_number: ^account_number}}
      assert_receive {:event, ^instance1, %MoneyDeposited{account_number: ^account_number}}
      refute_receive {:event, _pid, _event}

      assert ProcessRouter.process_instance(pid2, account_number) ==
               {:error, :process_manager_not_found}

      {:ok, account_number} = open_account(:example2)

      instance2 = wait_for_process_instance(pid2, account_number)

      assert_receive {:event, ^instance2, %BankAccountOpened{account_number: ^account_number}}
      assert_receive {:event, ^instance2, %MoneyDeposited{account_number: ^account_number}}
      refute_receive {:event, ^instance1, _event}
    end
  end

  defp start_reply_to_agent! do
    reply_to = self()

    start_supervised!(%{
      id: Agent,
      start: {Agent, :start_link, [fn -> reply_to end, [name: :reply_to]]}
    })
  end

  defp open_account(application, account_number \\ UUID.uuid4()) do
    command = %OpenAccount{account_number: account_number, initial_balance: 1_000}

    :ok = BankApp.dispatch(command, application: application)

    {:ok, account_number}
  end

  defp wait_for_process_instance(process_router, aggregate_uuid) do
    Wait.until(fn ->
      assert {:ok, process_instance} =
               ProcessRouter.process_instance(process_router, aggregate_uuid)

      process_instance
    end)
  end
end
