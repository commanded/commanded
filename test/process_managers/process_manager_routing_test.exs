defmodule Commanded.ProcessManagers.ProcessManagerRoutingTest do
  use Commanded.MockEventStoreCase

  alias Commanded.Helpers.EventFactory
  alias Commanded.Helpers.Wait
  alias Commanded.ProcessManagers.ProcessRouter
  alias Commanded.ProcessManagers.RoutingProcessManager
  alias Commanded.ProcessManagers.RoutingProcessManager.Continued
  alias Commanded.ProcessManagers.RoutingProcessManager.Errored
  alias Commanded.ProcessManagers.RoutingProcessManager.Started
  alias Commanded.ProcessManagers.RoutingProcessManager.Stopped
  alias Commanded.UUID

  setup do
    mock_event_store()

    {:ok, pid} = RoutingProcessManager.start_link()

    [pid: pid, process_uuid: UUID.uuid4()]
  end

  describe "process manager routing" do
    test "should start instance on `:start`", %{pid: pid, process_uuid: process_uuid} do
      send_events(pid, [%Started{process_uuid: process_uuid, reply_to: self()}])

      instance = wait_for_instance(pid, process_uuid)

      assert_receive {:started, ^instance}
    end

    test "should continue existing instance on `:start`", %{pid: pid, process_uuid: process_uuid} do
      send_events(pid, [
        %Started{process_uuid: process_uuid, reply_to: self()},
        %Started{process_uuid: process_uuid, reply_to: self()}
      ])

      instance = wait_for_instance(pid, process_uuid)

      assert_receive {:started, ^instance}
      assert_receive {:started, ^instance}
    end

    test "should continue instance on `:continue`", %{pid: pid, process_uuid: process_uuid} do
      send_events(pid, [
        %Started{process_uuid: process_uuid, reply_to: self()},
        %Continued{process_uuid: process_uuid, reply_to: self()}
      ])

      instance = wait_for_instance(pid, process_uuid)

      assert_receive {:started, ^instance}
      assert_receive {:continued, ^instance}
    end

    test "should start instance on `:continue`", %{pid: pid, process_uuid: process_uuid} do
      send_events(pid, [%Continued{process_uuid: process_uuid, reply_to: self()}])

      instance = wait_for_instance(pid, process_uuid)

      refute_receive {:started, ^instance}
      assert_receive {:continued, ^instance}
    end

    test "should stop instance on `:stop`", %{pid: pid, process_uuid: process_uuid} do
      expect(MockEventStore, :delete_snapshot, fn _event_store, _process_uuid -> :ok end)

      send_events(pid, [%Started{process_uuid: process_uuid, reply_to: self()}])

      instance = wait_for_instance(pid, process_uuid)
      ref = Process.monitor(instance)

      send_events(pid, [%Stopped{process_uuid: process_uuid}], 2)

      assert_receive {:started, ^instance}
      assert_receive {:DOWN, ^ref, :process, ^instance, :normal}
    end

    test "should ignore an empty list returned on `:start`", %{
      pid: pid,
      process_uuid: process_uuid
    } do
      send_events(pid, [
        %Started{process_uuid: [], reply_to: self()},
        %Started{process_uuid: process_uuid, reply_to: self()}
      ])

      instance = wait_for_instance(pid, process_uuid)

      assert_receive {:started, ^instance}
      refute_receive {:started, _instance}
    end
  end

  describe "process manager strict routing" do
    test "should start instance on `:start!`", %{pid: pid, process_uuid: process_uuid} do
      send_events(pid, [%Started{process_uuid: process_uuid, reply_to: self(), strict?: true}])

      instance = wait_for_instance(pid, process_uuid)

      assert_receive {:started, ^instance}
    end

    test "should error on `:start!` when instance already started", %{
      pid: pid,
      process_uuid: process_uuid
    } do
      Process.unlink(pid)
      ref = Process.monitor(pid)

      send_events(pid, [
        %Started{process_uuid: process_uuid, reply_to: self(), strict?: true},
        %Started{process_uuid: process_uuid, reply_to: self(), strict?: true}
      ])

      assert_receive {:started, _instance}
      refute_receive {:started, _instance}
      assert_receive {:error, {:start!, :process_already_started}}
      assert_receive {:DOWN, ^ref, :process, ^pid, {:start!, :process_already_started}}
    end

    test "should continue instance on `:continue!`", %{pid: pid, process_uuid: process_uuid} do
      send_events(pid, [
        %Started{process_uuid: process_uuid, reply_to: self(), strict?: true},
        %Continued{process_uuid: process_uuid, reply_to: self(), strict?: true}
      ])

      instance = wait_for_instance(pid, process_uuid)

      assert_receive {:started, ^instance}
      assert_receive {:continued, ^instance}
    end

    test "should error on `:continue` when instance not already started", %{
      pid: pid,
      process_uuid: process_uuid
    } do
      Process.unlink(pid)
      ref = Process.monitor(pid)

      send_events(pid, [%Continued{process_uuid: process_uuid, reply_to: self(), strict?: true}])

      refute_receive {:continued, _instance}
      assert_receive {:error, {:continue!, :process_not_started}}
      assert_receive {:DOWN, ^ref, :process, ^pid, {:continue!, :process_not_started}}
    end

    test "should rescue `interested?` errors", %{
      pid: pid,
      process_uuid: process_uuid
    } do
      Process.unlink(pid)
      ref = Process.monitor(pid)

      send_events(pid, [
        %Errored{process_uuid: process_uuid, reply_to: self(), on_error: {:stop, :error}}
      ])

      assert_receive {:error, %RuntimeError{message: "error"}}
      assert_receive {:DOWN, ^ref, :process, ^pid, :error}
    end

    test "should continue processing events after `:skip` error", %{
      pid: pid,
      process_uuid: process_uuid
    } do
      ref = Process.monitor(pid)

      send_events(pid, [
        %Started{process_uuid: process_uuid, reply_to: self()},
        %Errored{process_uuid: process_uuid, reply_to: self(), on_error: :skip},
        %Continued{process_uuid: process_uuid, reply_to: self()}
      ])

      instance = wait_for_instance(pid, process_uuid)

      assert_receive {:started, ^instance}
      assert_receive {:error, %RuntimeError{message: "error"}}
      assert_receive {:continued, ^instance}
      refute_receive {:DOWN, ^ref, :process, ^pid, _}
    end
  end

  defp mock_event_store do
    expect(MockEventStore, :subscribe_to, fn
      _event_store, :all, name, pid, :origin, _opts ->
        assert is_binary(name)
        assert is_pid(pid)

        send(pid, {:subscribed, self()})

        {:ok, self()}
    end)

    stub(MockEventStore, :read_snapshot, fn _event_store, _snapshot_uuid ->
      {:error, :snapshot_not_found}
    end)

    stub(MockEventStore, :record_snapshot, fn _event_store, _snapshot -> :ok end)
    stub(MockEventStore, :ack_event, fn _event_store, _pid, _event -> :ok end)
  end

  defp send_events(pid, events, initial_event_number \\ 1) do
    recorded_events = EventFactory.map_to_recorded_events(events, initial_event_number)

    send(pid, {:events, recorded_events})
  end

  defp wait_for_instance(pid, process_uuid) do
    Wait.until(fn ->
      assert {:ok, instance} = ProcessRouter.process_instance(pid, process_uuid)

      instance
    end)
  end
end
