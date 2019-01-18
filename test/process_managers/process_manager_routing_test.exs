defmodule Commanded.ProcessManagers.ProcessManagerRoutingTest do
  use Commanded.MockEventStoreCase

  alias Commanded.Helpers.EventFactory
  alias Commanded.Helpers.Wait
  alias Commanded.ProcessManagers.ProcessRouter

  defmodule Started do
    @enforce_keys [:process_uuid]
    defstruct [:process_uuid, :reply_to, strict?: false]
  end

  defmodule Continued do
    @enforce_keys [:process_uuid]
    defstruct [:process_uuid, :reply_to, strict?: false]
  end

  defmodule Stopped do
    @enforce_keys [:process_uuid]
    defstruct [:process_uuid]
  end

  defmodule ProcessManager do
    use Commanded.ProcessManagers.ProcessManager,
      name: __MODULE__,
      router: Commanded.Commands.MockRouter

    alias Commanded.ProcessManagers.FailureContext

    defstruct [:processes]

    def interested?(%Started{process_uuid: process_uuid, strict?: true}),
      do: {:start!, process_uuid}

    def interested?(%Started{process_uuid: process_uuid}),
      do: {:start, process_uuid}

    def interested?(%Continued{process_uuid: process_uuid, strict?: true}),
      do: {:continue!, process_uuid}

    def interested?(%Continued{process_uuid: process_uuid}),
      do: {:continue, process_uuid}

    def interested?(%Stopped{process_uuid: process_uuid}),
      do: {:stop, process_uuid}

    def handle(%ProcessManager{}, %Started{} = event) do
      %Started{reply_to: reply_to} = event

      send(reply_to, {:started, self()})

      []
    end

    def handle(%ProcessManager{}, %Continued{} = event) do
      %Continued{reply_to: reply_to} = event

      send(reply_to, {:continue, self()})

      []
    end

    def error({:error, error}, %Started{} = event, %FailureContext{}) do
      %Started{reply_to: reply_to} = event

      send(reply_to, {:error, error})

      {:stop, error}
    end

    def error({:error, error}, %Continued{} = event, %FailureContext{}) do
      %Continued{reply_to: reply_to} = event

      send(reply_to, {:error, error})

      {:stop, error}
    end
  end

  setup do
    expect(MockEventStore, :subscribe_to, fn
      :all, _name, pid, :origin ->
        send(pid, {:subscribed, self()})

        {:ok, self()}
    end)

    stub(MockEventStore, :read_snapshot, fn _snapshot_uuid -> {:error, :snapshot_not_found} end)
    stub(MockEventStore, :record_snapshot, fn _snapshot -> :ok end)
    stub(MockEventStore, :ack_event, fn _pid, _event -> :ok end)

    {:ok, pid} = ProcessManager.start_link()

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
      assert_receive {:continue, ^instance}
    end

    test "should start instance on `:continue`", %{pid: pid, process_uuid: process_uuid} do
      send_events(pid, [%Continued{process_uuid: process_uuid, reply_to: self()}])

      instance = wait_for_instance(pid, process_uuid)

      refute_receive {:started, ^instance}
      assert_receive {:continue, ^instance}
    end

    test "should stop instance on `:stop`", %{pid: pid, process_uuid: process_uuid} do
      expect(MockEventStore, :delete_snapshot, fn _process_uuid -> :ok end)

      send_events(pid, [%Started{process_uuid: process_uuid, reply_to: self()}])

      instance = wait_for_instance(pid, process_uuid)
      ref = Process.monitor(instance)

      send_events(pid, [%Stopped{process_uuid: process_uuid}], 2)

      assert_receive {:started, ^instance}
      assert_receive {:DOWN, ^ref, :process, ^instance, :normal}
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
      assert_receive {:continue, ^instance}
    end

    test "should error on `:continue` when instance not already started", %{
      pid: pid,
      process_uuid: process_uuid
    } do
      Process.unlink(pid)
      ref = Process.monitor(pid)

      send_events(pid, [%Continued{process_uuid: process_uuid, reply_to: self(), strict?: true}])

      refute_receive {:continue, _instance}
      assert_receive {:error, {:continue!, :process_not_started}}
      assert_receive {:DOWN, ^ref, :process, ^pid, {:continue!, :process_not_started}}
    end
  end

  defp send_events(pid, events, initial_event_number \\ 1) do
    recorded_events = EventFactory.map_to_recorded_events(events, initial_event_number)

    send(pid, {:events, recorded_events})
  end

  defp wait_for_instance(pid, process_uuid) do
    Wait.until(fn ->
      instance = ProcessRouter.process_instance(pid, process_uuid)

      assert is_pid(instance)

      instance
    end)
  end
end
