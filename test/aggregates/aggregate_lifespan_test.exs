defmodule Commanded.Aggregates.AggregateLifespanTest do
  use ExUnit.Case

  alias Commanded.Aggregates.{DefaultLifespanRouter, LifespanAggregate, LifespanRouter}
  alias Commanded.Aggregates.LifespanAggregate.{Command, Event}
  alias Commanded.{DefaultApp, EventStore}
  alias Commanded.EventStore.RecordedEvent
  alias Commanded.{Registration, UUID}

  describe "aggregate lifespan" do
    setup do
      aggregate_uuid = UUID.uuid4()

      start_supervised!(
        {DefaultApp,
         snapshotting: %{LifespanAggregate => [snapshot_every: 2, snapshot_version: 1]}}
      )

      {:ok, ^aggregate_uuid} =
        Commanded.Aggregates.Supervisor.open_aggregate(
          DefaultApp,
          LifespanAggregate,
          aggregate_uuid
        )

      pid = Registration.whereis_name(DefaultApp, {DefaultApp, LifespanAggregate, aggregate_uuid})
      ref = Process.monitor(pid)
      reply_to = :erlang.pid_to_list(self())

      %{aggregate_uuid: aggregate_uuid, pid: pid, ref: ref, reply_to: reply_to}
    end

    test "should use default `after_event/1` lifespan when none specified'", %{
      aggregate_uuid: aggregate_uuid,
      ref: ref
    } do
      command = %Command{uuid: aggregate_uuid, action: :event}

      assert :ok = DefaultLifespanRouter.dispatch(command, application: DefaultApp)

      refute_receive {:DOWN, ^ref, :process, _pid, _reason}
    end

    test "should use default `after_command/1` lifespan when none specified'", %{
      aggregate_uuid: aggregate_uuid,
      ref: ref
    } do
      command = %Command{uuid: aggregate_uuid, action: :noop}

      assert :ok = DefaultLifespanRouter.dispatch(command, application: DefaultApp)

      refute_receive {:DOWN, ^ref, :process, _pid, _reason}
    end

    test "should use default `after_error/1` lifespan when none specified'", %{
      aggregate_uuid: aggregate_uuid,
      ref: ref
    } do
      command = %Command{uuid: aggregate_uuid, action: :error}

      {:error, {:failed, nil, nil}} =
        DefaultLifespanRouter.dispatch(command, application: DefaultApp)

      refute_receive {:DOWN, ^ref, :process, _pid, _reason}
    end

    test "should call `after_event/1` callback function", %{
      aggregate_uuid: aggregate_uuid,
      reply_to: reply_to
    } do
      command = %Command{
        uuid: aggregate_uuid,
        action: :event,
        reply_to: reply_to,
        lifespan: :stop
      }

      :ok = LifespanRouter.dispatch(command, application: DefaultApp)

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

      :ok = LifespanRouter.dispatch(command, application: DefaultApp)

      assert_receive {:DOWN, ^ref, :process, _pid, :normal}
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

      :ok = LifespanRouter.dispatch(command, application: DefaultApp)

      assert_receive :after_command
      refute_received :after_event
      refute_received :after_error
    end

    test "should shutdown after `after_command/1` timeout", %{
      aggregate_uuid: aggregate_uuid,
      ref: ref,
      reply_to: reply_to
    } do
      command = %Command{
        uuid: aggregate_uuid,
        action: :noop,
        reply_to: reply_to,
        lifespan: :stop
      }

      :ok = LifespanRouter.dispatch(command, application: DefaultApp)

      assert_receive {:DOWN, ^ref, :process, _pid, :normal}
    end

    test "should call `after_error/1` callback function on error", %{
      aggregate_uuid: aggregate_uuid,
      reply_to: reply_to
    } do
      command = %Command{
        uuid: aggregate_uuid,
        action: :error,
        reply_to: reply_to,
        lifespan: :stop
      }

      {:error, {:failed, _reply_to, :stop}} =
        LifespanRouter.dispatch(command, application: DefaultApp)

      assert_receive :after_error
      refute_received :after_event
      refute_received :after_command
    end

    test "should shutdown after `after_error/1` timeout", %{
      aggregate_uuid: aggregate_uuid,
      ref: ref,
      reply_to: reply_to
    } do
      command = %Command{
        uuid: aggregate_uuid,
        action: :error,
        reply_to: reply_to,
        lifespan: :stop
      }

      {:error, {:failed, _reply_to, :stop}} =
        LifespanRouter.dispatch(command, application: DefaultApp)

      assert_receive {:DOWN, ^ref, :process, _pid, :normal}
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

      :ok = LifespanRouter.dispatch(command, application: DefaultApp)
      :ok = LifespanRouter.dispatch(command, application: DefaultApp)

      assert_receive :after_command
      assert_receive :after_command

      refute_receive {:DOWN, ^ref, :process, _pid, _reason}, 25
      assert_receive {:DOWN, ^ref, :process, _pid, :normal}
    end

    test "should reopen the aggregate to execute command if it is stopped by the previous command",
         %{
           aggregate_uuid: aggregate_uuid,
           ref: ref
         } do
      command = %Command{uuid: aggregate_uuid, action: :noop, lifespan: :stop}

      tasks =
        for _i <- 1..3 do
          Task.async(fn ->
            :ok = LifespanRouter.dispatch(command, application: DefaultApp)
          end)
        end

      Task.yield_many(tasks)

      assert_receive {:DOWN, ^ref, :process, _pid, :normal}
    end

    test "should reopen the aggregate to execute command if it is stopped by an error",
         %{
           aggregate_uuid: aggregate_uuid,
           ref: ref
         } do
      command = %Command{uuid: aggregate_uuid, action: :error, lifespan: :stop}

      tasks =
        for _i <- 1..3 do
          Task.async(fn ->
            {:error, {:failed, nil, :stop}} =
              LifespanRouter.dispatch(command, application: DefaultApp)
          end)
        end

      Task.yield_many(tasks)

      assert_receive {:DOWN, ^ref, :process, _pid, :normal}
    end

    test "should stop process when requested", %{
      aggregate_uuid: aggregate_uuid,
      ref: ref
    } do
      command = %Command{uuid: aggregate_uuid, action: :noop, lifespan: :stop}

      :ok = LifespanRouter.dispatch(command, application: DefaultApp)

      assert_receive {:DOWN, ^ref, :process, _pid, :normal}
    end

    test "should adhere to aggregate lifespan after taking snapshot",
         %{
           aggregate_uuid: aggregate_uuid,
           ref: ref
         } do
      command = %Command{
        uuid: aggregate_uuid,
        action: :event,
        lifespan: :infinity
      }

      :ok = LifespanRouter.dispatch(command, application: DefaultApp)

      command = %Command{
        uuid: aggregate_uuid,
        action: :event,
        lifespan: :stop
      }

      :ok = LifespanRouter.dispatch(command, application: DefaultApp)

      assert_receive {:DOWN, ^ref, :process, _pid, :normal}
      assert {:ok, _snapshot} = EventStore.read_snapshot(DefaultApp, aggregate_uuid)
    end

    test "should adhere to aggregate lifespan when receiving published events after taking snapshot",
         %{
           aggregate_uuid: aggregate_uuid,
           pid: pid,
           ref: ref
         } do
      command = %Command{
        uuid: aggregate_uuid,
        action: :event,
        lifespan: :infinity
      }

      :ok = LifespanRouter.dispatch(command, application: DefaultApp)

      command = %Command{
        uuid: aggregate_uuid,
        action: :event,
        lifespan: 1
      }

      :ok = LifespanRouter.dispatch(command, application: DefaultApp)

      assert Process.alive?(pid)

      events = EventStore.stream_forward(DefaultApp, aggregate_uuid) |> Enum.to_list()

      # Publish events to aggregate after taking snapshot
      send(pid, {:events, events})

      assert_receive {:DOWN, ^ref, :process, _pid, :normal}
      assert {:ok, _snapshot} = EventStore.read_snapshot(DefaultApp, aggregate_uuid)
    end

    test "should use `:infinity` lifespan by default", %{
      aggregate_uuid: aggregate_uuid,
      pid: pid,
      ref: ref
    } do
      events = [
        %RecordedEvent{
          event_id: UUID.uuid4(),
          event_number: 1,
          data: %Event{uuid: aggregate_uuid}
        }
      ]

      # Simulate sending an event directly to the aggregate process
      send(pid, {:events, events})

      refute_receive {:DOWN, ^ref, :process, ^pid, _}
    end
  end
end
