defmodule Commanded.Aggregates.AggregateLifespanTest do
  use Commanded.StorageCase

  alias Commanded.DefaultApp
  alias Commanded.Aggregates.{DefaultLifespanRouter, LifespanAggregate, LifespanRouter}
  alias Commanded.Aggregates.LifespanAggregate.{Command, Event}
  alias Commanded.EventStore
  alias Commanded.EventStore.RecordedEvent
  alias Commanded.Registration

  describe "aggregate lifespan" do
    setup do
      aggregate_uuid = UUID.uuid4()

      start_supervised!(DefaultApp)

      {:ok, ^aggregate_uuid} =
        Commanded.Aggregates.Supervisor.open_aggregate(
          DefaultApp,
          LifespanAggregate,
          aggregate_uuid
        )

      pid = Registration.whereis_name(DefaultApp, {DefaultApp, LifespanAggregate, aggregate_uuid})
      ref = Process.monitor(pid)
      reply_to = self() |> :erlang.pid_to_list()

      %{aggregate_uuid: aggregate_uuid, pid: pid, ref: ref, reply_to: reply_to}
    end

    test "should use default `after_event/1` lifespan when none specified'", %{
      aggregate_uuid: aggregate_uuid,
      ref: ref
    } do
      command = %Command{uuid: aggregate_uuid, action: :event}

      assert :ok = DefaultLifespanRouter.dispatch(command, application: DefaultApp)

      refute_receive {:DOWN, ^ref, :process, _, :normal}, 10
    end

    test "should use default `after_command/1` lifespan when none specified'", %{
      aggregate_uuid: aggregate_uuid,
      ref: ref
    } do
      command = %Command{uuid: aggregate_uuid, action: :noop}

      assert :ok = DefaultLifespanRouter.dispatch(command)

      refute_receive {:DOWN, ^ref, :process, _, :normal}, 10
    end

    test "should use default `after_error/1` lifespan when none specified'", %{
      aggregate_uuid: aggregate_uuid,
      ref: ref
    } do
      command = %Command{uuid: aggregate_uuid, action: :error}

      {:error, {:failed, nil, nil}} = DefaultLifespanRouter.dispatch(command)

      refute_receive {:DOWN, ^ref, :process, _, :normal}, 10
    end

    test "should call `after_event/1` callback function", %{
      aggregate_uuid: aggregate_uuid,
      reply_to: reply_to
    } do
      :ok =
        LifespanRouter.dispatch(%Command{
          uuid: aggregate_uuid,
          action: :event,
          reply_to: reply_to,
          lifespan: :stop
        })

      assert_receive :after_event
      refute_received :after_command
      refute_received :after_error
    end

    test "should shutdown after `after_event/1` timeout", %{
      aggregate_uuid: aggregate_uuid,
      ref: ref,
      reply_to: reply_to
    } do
      command = %Command{
        uuid: aggregate_uuid,
        action: :event,
        reply_to: reply_to,
        lifespan: :stop
      }

      :ok = LifespanRouter.dispatch(command)

      assert_receive {:DOWN, ^ref, :process, _, :normal}
    end

    test "should call `after_command/1` callback function when no domain events", %{
      aggregate_uuid: aggregate_uuid,
      reply_to: reply_to
    } do
      command = %Command{
        uuid: aggregate_uuid,
        action: :noop,
        reply_to: reply_to,
        lifespan: :stop
      }

      :ok = LifespanRouter.dispatch(command)

      assert_receive :after_command
      refute_received :after_event
      refute_received :after_error
    end

    test "should shutdown after `after_command/1` timeout", %{
      aggregate_uuid: aggregate_uuid,
      ref: ref,
      reply_to: reply_to
    } do
      :ok =
        LifespanRouter.dispatch(%Command{
          uuid: aggregate_uuid,
          action: :noop,
          reply_to: reply_to,
          lifespan: :stop
        })

      assert_receive {:DOWN, ^ref, :process, _, :normal}
    end

    test "should call `after_error/1` callback function on error", %{
      aggregate_uuid: aggregate_uuid,
      reply_to: reply_to
    } do
      {:error, {:failed, _reply_to, :stop}} =
        LifespanRouter.dispatch(%Command{
          uuid: aggregate_uuid,
          action: :error,
          reply_to: reply_to,
          lifespan: :stop
        })

      assert_receive :after_error
      refute_received :after_event
      refute_received :after_command
    end

    test "should shutdown after `after_error/1` timeout", %{
      aggregate_uuid: aggregate_uuid,
      ref: ref,
      reply_to: reply_to
    } do
      {:error, {:failed, _reply_to, :stop}} =
        LifespanRouter.dispatch(%Command{
          uuid: aggregate_uuid,
          action: :error,
          reply_to: reply_to,
          lifespan: :stop
        })

      assert_receive {:DOWN, ^ref, :process, _, :normal}
    end

    test "should not shutdown if another command executed", %{
      aggregate_uuid: aggregate_uuid,
      ref: ref,
      reply_to: reply_to
    } do
      command = %Command{
        uuid: aggregate_uuid,
        action: :noop,
        reply_to: reply_to,
        lifespan: 25
      }

      :ok = LifespanRouter.dispatch(command)
      :ok = LifespanRouter.dispatch(command)

      assert_receive :after_command
      assert_receive :after_command

      refute_receive {:DOWN, ^ref, :process, _, :normal}, 25
      assert_receive {:DOWN, ^ref, :process, _, :normal}
    end

    test "should stop process when requested", %{
      aggregate_uuid: aggregate_uuid,
      ref: ref
    } do
      :ok =
        LifespanRouter.dispatch(%Command{uuid: aggregate_uuid, action: :noop, lifespan: :stop})

      assert_receive {:DOWN, ^ref, :process, _, :normal}
    end

    test "should adhere to aggregate lifespan after taking snapshot",
         %{
           aggregate_uuid: aggregate_uuid,
           ref: ref
         } do
      :ok =
        LifespanRouter.dispatch(%Command{
          uuid: aggregate_uuid,
          action: :event,
          lifespan: :infinity
        })

      :ok =
        LifespanRouter.dispatch(%Command{
          uuid: aggregate_uuid,
          action: :event,
          lifespan: :stop
        })

      assert_receive {:DOWN, ^ref, :process, _, :normal}
      assert {:ok, _snapshot} = EventStore.read_snapshot(aggregate_uuid)
    end

    test "should adhere to aggregate lifespan when receiving published events after taking snapshot",
         %{
           aggregate_uuid: aggregate_uuid,
           pid: pid,
           ref: ref
         } do
      :ok =
        LifespanRouter.dispatch(%Command{
          uuid: aggregate_uuid,
          action: :event,
          lifespan: :infinity
        })

      :ok =
        LifespanRouter.dispatch(%Command{
          uuid: aggregate_uuid,
          action: :event,
          lifespan: 1
        })

      assert Process.alive?(pid)

      events = aggregate_uuid |> EventStore.stream_forward() |> Enum.to_list()

      # Publish events to aggregate after taking snapshot
      send(pid, {:events, events})

      assert_receive {:DOWN, ^ref, :process, _, :normal}
      assert {:ok, _snapshot} = EventStore.read_snapshot(aggregate_uuid)
    end

    test "should use `:infinity` lifespan by default", %{
      aggregate_uuid: aggregate_uuid,
      pid: pid,
      ref: ref
    } do
      events = [
        %RecordedEvent{
          event_id: UUID.uuid4(),
          stream_version: 1,
          data: %Event{uuid: aggregate_uuid}
        }
      ]

      # Simulate sending an event directly to the aggregate process
      send(pid, {:events, events})

      refute_receive {:DOWN, ^ref, :process, ^pid, _}
    end
  end

  describe "compile time safety" do
    test "should fail to compile when missing `after_event/1` function" do
      assert_raise ArgumentError,
                   "Aggregate lifespan `BankAccountLifespan1` does not define a callback function: `after_event/1`",
                   fn ->
                     Code.eval_string("""
                       alias Commanded.ExampleDomain.BankAccount
                       alias Commanded.ExampleDomain.BankAccount.Commands.{OpenAccount, DepositMoney}

                       defmodule BankAccountLifespan1 do
                       end

                       defmodule BankRouter do
                         use Commanded.Commands.Router

                         dispatch [OpenAccount],
                           to: BankAccount,
                           lifespan: BankAccountLifespan1,
                           identity: :account_number
                       end
                     """)
                   end
    end

    test "should fail to compile when missing `after_command/1` function" do
      assert_raise ArgumentError,
                   "Aggregate lifespan `BankAccountLifespan2` does not define a callback function: `after_command/1`",
                   fn ->
                     Code.eval_string("""
                       alias Commanded.ExampleDomain.BankAccount
                       alias Commanded.ExampleDomain.BankAccount.Commands.{OpenAccount, DepositMoney}

                       defmodule BankAccountLifespan2 do
                         def after_event(_event), do: :stop
                       end

                       defmodule BankRouter do
                         use Commanded.Commands.Router

                         dispatch [OpenAccount],
                           to: BankAccount,
                           lifespan: BankAccountLifespan2,
                           identity: :account_number
                       end
                     """)
                   end
    end
  end
end
