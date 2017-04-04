defmodule Commanded.EventStoreAdapter.SnapshotTest do
  use Commanded.StorageCase
  use Commanded.EventStore

  alias Commanded.EventStore.{
    EventData,
    SnapshotData,
  }
  alias Commanded.ExampleDomain.BankAccount.Events.BankAccountOpened

  require Logger

  defp create_test_event(account_number) do
    %EventData{
      correlation_id: UUID.uuid4,
      event_type: "Elixir.Commanded.ExampleDomain.BankAccount.Events.BankAccountOpened",
      data: %BankAccountOpened{account_number: account_number, initial_balance: 1_000},
      metadata: nil
    }
  end

  defp new_test_events(count) do
    for account_number <- 1..count do
      create_test_event(account_number)
    end
  end

  defp create_snapshot_data(account_number) do
    %SnapshotData{
      source_uuid: UUID.uuid4,
      source_version: account_number,
      source_type: "Elixir.Commanded.ExampleDomain.BankAccount.Events.BankAccountOpened",
      data:  %BankAccountOpened{account_number: account_number, initial_balance: 1_000},
      metadata: nil,
      created_at: DateTime.to_naive(DateTime.utc_now())
    }
  end

  defp snapshot_created_at_seconds_to_zero(snapshot) do
    %NaiveDateTime{year: year, month: month, day: day, hour: hour, minute: min} = snapshot.created_at
    {:ok, zeroed_created_at} = NaiveDateTime.new(year, month, day, hour, min, 0, 0)

    %SnapshotData{snapshot | created_at: zeroed_created_at}
  end

  # test "should record a snapshot" do
  #   snapshot = create_snapshot_data(100)
  #
  #   assert :ok = @event_store.record_snapshot(snapshot)
  # end
  #
  # test "should read a snapshot" do
  #   snapshot1 = create_snapshot_data(100)
  #   snapshot2 = create_snapshot_data(101)
  #   snapshot3 = create_snapshot_data(102)
  #
  #   assert :ok == @event_store.record_snapshot(snapshot1)
  #   assert :ok == @event_store.record_snapshot(snapshot2)
  #   assert :ok == @event_store.record_snapshot(snapshot3)
  #
  #   {:ok, snapshot} = @event_store.read_snapshot(snapshot3.source_uuid)
  #   assert snapshot_created_at_seconds_to_zero(snapshot) == snapshot_created_at_seconds_to_zero(snapshot3)
  # end
  #
  # test "should delete a snapshot" do
  #   snapshot1 = create_snapshot_data(100)
  #
  #   assert :ok == @event_store.record_snapshot(snapshot1)
  #   {:ok, snapshot} = @event_store.read_snapshot(snapshot1.source_uuid)
  #   assert snapshot_created_at_seconds_to_zero(snapshot) == snapshot_created_at_seconds_to_zero(snapshot1)
  #
  #   assert :ok == @event_store.delete_snapshot(snapshot1.source_uuid)
  #   assert {:error, :snapshot_not_found} == @event_store.read_snapshot(snapshot1.source_uuid)
  # end
end
