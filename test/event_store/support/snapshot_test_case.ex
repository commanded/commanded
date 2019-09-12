defmodule Commanded.EventStore.SnapshotTestCase do
  import Commanded.SharedTestCase

  define_tests do
    alias Commanded.EventStore
    alias Commanded.EventStore.SnapshotData

    defmodule BankAccountOpened do
      @derive Jason.Encoder
      defstruct [:account_number, :initial_balance]
    end

    setup %{application: application} do
      start_supervised!(application)

      :ok
    end

    describe "record a snapshot" do
      test "should record the snapshot", %{application: application} do
        snapshot = build_snapshot_data(100)

        assert :ok = EventStore.record_snapshot(application, snapshot)
      end
    end

    describe "read a snapshot" do
      test "should read the snapshot", %{application: application} do
        snapshot1 = build_snapshot_data(100)
        snapshot2 = build_snapshot_data(101)
        snapshot3 = build_snapshot_data(102)

        assert :ok == EventStore.record_snapshot(application, snapshot1)
        assert :ok == EventStore.record_snapshot(application, snapshot2)
        assert :ok == EventStore.record_snapshot(application, snapshot3)

        {:ok, snapshot} = EventStore.read_snapshot(application, snapshot3.source_uuid)

        assert snapshot_timestamps_within_delta?(snapshot, snapshot3, 60)
      end

      test "should error when snapshot does not exist", %{application: application} do
        {:error, :snapshot_not_found} = EventStore.read_snapshot(application, "doesnotexist")
      end
    end

    describe "delete a snapshot" do
      test "should delete the snapshot", %{application: application} do
        snapshot1 = build_snapshot_data(100)

        assert :ok == EventStore.record_snapshot(application, snapshot1)
        {:ok, snapshot} = EventStore.read_snapshot(application, snapshot1.source_uuid)

        assert snapshot_timestamps_within_delta?(snapshot, snapshot1, 60)
        assert :ok == EventStore.delete_snapshot(application, snapshot1.source_uuid)

        assert {:error, :snapshot_not_found} ==
                 EventStore.read_snapshot(application, snapshot1.source_uuid)
      end
    end

    defp build_snapshot_data(account_number) do
      %SnapshotData{
        source_uuid: UUID.uuid4(),
        source_version: account_number,
        source_type: "#{__MODULE__}.BankAccountOpened",
        data: %BankAccountOpened{account_number: account_number, initial_balance: 1_000},
        metadata: nil,
        created_at: DateTime.utc_now()
      }
    end

    defp snapshot_timestamps_within_delta?(snapshot, other_snapshot, delta_seconds) do
      DateTime.diff(snapshot.created_at, other_snapshot.created_at, :second) < delta_seconds
    end
  end
end
