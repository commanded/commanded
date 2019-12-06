defmodule Commanded.DynamicApplicationsTest do
  use ExUnit.Case

  alias Commanded.ExampleApplication
  alias Commanded.ExampleDomain.BankAccount.Commands.OpenAccount
  alias Commanded.ExampleProcessManager
  alias Commanded.Helpers.CommandAuditMiddleware
  alias Commanded.Helpers.Wait
  alias Commanded.ReplyHandler
  alias Commanded.ProcessManagers.ProcessRouter

  setup_all do
    start_supervised!(CommandAuditMiddleware)
    :ok
  end

  describe "dynamic Commanded applications" do
    test "should ensure name is an atom" do
      assert_raise ArgumentError,
                   "expected :name option to be an atom but got: \"invalid\"",
                   fn -> ExampleApplication.start_link(name: "invalid") end
    end

    test "should allow name to be provided when starting an application" do
      assert {:ok, pid} = start_supervised({ExampleApplication, name: :example1})
      assert Process.whereis(:example1) == pid
    end

    test "should not allow an application to be started more than once with the same name" do
      assert {:ok, pid} = start_supervised({ExampleApplication, name: :example1})
      assert {:error, {:already_started, ^pid}} = ExampleApplication.start_link(name: :example1)
    end

    test "should allow the same application to be started multiple times with dynamic names" do
      assert {:ok, pid1} = start_supervised({ExampleApplication, name: :example1})
      assert {:ok, pid2} = start_supervised({ExampleApplication, name: :example2})
      assert {:ok, pid3} = start_supervised({ExampleApplication, name: :example3})

      assert length(Enum.uniq([pid1, pid2, pid3])) == 3
    end
  end

  describe "dynamic application command dispatch" do
    setup do
      start_supervised!({ExampleApplication, name: :example1})
      start_supervised!({ExampleApplication, name: :example2})
      :ok
    end

    test "should dispatch to named application" do
      {:ok, account_number} = open_account(:example1)

      assert Commanded.EventStore.stream_forward(:example1, account_number) |> length() == 1

      assert {:error, :stream_not_found} =
               Commanded.EventStore.stream_forward(:example2, account_number)

      {:ok, ^account_number} = open_account(:example2, account_number)

      assert Commanded.EventStore.stream_forward(:example1, account_number) |> length() == 1
      assert Commanded.EventStore.stream_forward(:example2, account_number) |> length() == 1
    end

    test "should error without application name" do
      account_number = UUID.uuid4()
      command = %OpenAccount{account_number: account_number, initial_balance: 1_000}

      assert_raise RuntimeError, fn ->
        :ok = ExampleApplication.dispatch(command)
      end
    end
  end

  describe "dynamic application event handler" do
    setup do
      start_reply_to_agent!()
      start_supervised!({ExampleApplication, name: :example1})
      start_supervised!({ExampleApplication, name: :example2})
      :ok
    end

    test "should only receive events from named application" do
      pid1 = start_supervised!({ReplyHandler, application: :example1})
      pid2 = start_supervised!({ReplyHandler, application: :example2})

      {:ok, _account_number} = open_account(:example1)

      assert_receive {:event, ^pid1, _event}
      refute_receive {:event, ^pid2, _event}

      {:ok, _account_number} = open_account(:example2)

      assert_receive {:event, ^pid2, _event}
      refute_receive {:event, ^pid1, _event}
    end
  end

  describe "dynamic application process manager" do
    setup do
      start_reply_to_agent!()
      start_supervised!({ExampleApplication, name: :example1})
      start_supervised!({ExampleApplication, name: :example2})
      :ok
    end

    test "should only receive events from named application" do
      pid1 = start_supervised!({ExampleProcessManager, application: :example1})
      pid2 = start_supervised!({ExampleProcessManager, application: :example2})

      {:ok, account_number} = open_account(:example1)

      instance1 = wait_for_process_instance(pid1, account_number)

      assert is_pid(instance1)
      assert_receive {:event, ^instance1, _event}

      assert ProcessRouter.process_instance(pid2, account_number) ==
               {:error, :process_manager_not_found}

      refute_receive {:event, _pid, _event}

      {:ok, account_number} = open_account(:example2)

      instance2 = wait_for_process_instance(pid2, account_number)

      assert is_pid(instance2)
      assert_receive {:event, ^instance2, _event}
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

    :ok = ExampleApplication.dispatch(command, application: application)

    {:ok, account_number}
  end

  defp wait_for_process_instance(process_router, aggregate_uuid) do
    Wait.until(fn ->
      process_instance = ProcessRouter.process_instance(process_router, aggregate_uuid)

      assert is_pid(process_instance)

      process_instance
    end)
  end
end
