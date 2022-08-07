defmodule Commanded.EventStore.AppendEventsTestCase do
  import Commanded.SharedTestCase

  define_tests do
    import Commanded.Enumerable, only: [pluck: 2]

    alias Commanded.EventStore.EventData
    alias Commanded.UUID

    defmodule BankAccountOpened do
      @derive Jason.Encoder
      defstruct [:account_number, :initial_balance]
    end

    describe "event store adapter" do
      test "should implement `Commanded.EventStore.Adapter` behaviour", %{
        event_store: event_store
      } do
        assert_implements(event_store, Commanded.EventStore.Adapter)
      end
    end

    describe "append events to a stream" do
      test "should append events", %{event_store: event_store, event_store_meta: event_store_meta} do
        assert :ok == event_store.append_to_stream(event_store_meta, "stream", 0, build_events(1))
        assert :ok == event_store.append_to_stream(event_store_meta, "stream", 1, build_events(2))
        assert :ok == event_store.append_to_stream(event_store_meta, "stream", 3, build_events(3))
      end

      test "should append events with `:any_version` without checking expected version", %{
        event_store: event_store,
        event_store_meta: event_store_meta
      } do
        assert :ok ==
                 event_store.append_to_stream(
                   event_store_meta,
                   "stream",
                   :any_version,
                   build_events(3)
                 )

        assert :ok ==
                 event_store.append_to_stream(
                   event_store_meta,
                   "stream",
                   :any_version,
                   build_events(2)
                 )

        assert :ok ==
                 event_store.append_to_stream(
                   event_store_meta,
                   "stream",
                   :any_version,
                   build_events(1)
                 )
      end

      test "should append events with `:no_stream` parameter", %{
        event_store: event_store,
        event_store_meta: event_store_meta
      } do
        assert :ok ==
                 event_store.append_to_stream(
                   event_store_meta,
                   "stream",
                   :no_stream,
                   build_events(2)
                 )
      end

      test "should fail when stream already exists with `:no_stream` parameter", %{
        event_store: event_store,
        event_store_meta: event_store_meta
      } do
        assert :ok ==
                 event_store.append_to_stream(
                   event_store_meta,
                   "stream",
                   :no_stream,
                   build_events(2)
                 )

        assert {:error, :stream_exists} ==
                 event_store.append_to_stream(
                   event_store_meta,
                   "stream",
                   :no_stream,
                   build_events(1)
                 )
      end

      test "should append events with `:stream_exists` parameter", %{
        event_store: event_store,
        event_store_meta: event_store_meta
      } do
        assert :ok ==
                 event_store.append_to_stream(
                   event_store_meta,
                   "stream",
                   :no_stream,
                   build_events(2)
                 )

        assert :ok ==
                 event_store.append_to_stream(
                   event_store_meta,
                   "stream",
                   :stream_exists,
                   build_events(1)
                 )
      end

      test "should fail with `:stream_exists` parameter when stream does not exist", %{
        event_store: event_store,
        event_store_meta: event_store_meta
      } do
        assert {:error, :stream_not_found} ==
                 event_store.append_to_stream(
                   event_store_meta,
                   "stream",
                   :stream_exists,
                   build_events(1)
                 )
      end

      test "should fail to append to a stream because of wrong expected version when no stream",
           %{event_store: event_store, event_store_meta: event_store_meta} do
        assert {:error, :wrong_expected_version} ==
                 event_store.append_to_stream(event_store_meta, "stream", 1, build_events(1))
      end

      test "should fail to append to a stream because of wrong expected version", %{
        event_store: event_store,
        event_store_meta: event_store_meta
      } do
        assert :ok == event_store.append_to_stream(event_store_meta, "stream", 0, build_events(3))

        assert {:error, :wrong_expected_version} ==
                 event_store.append_to_stream(event_store_meta, "stream", 0, build_events(1))

        assert {:error, :wrong_expected_version} ==
                 event_store.append_to_stream(event_store_meta, "stream", 1, build_events(1))

        assert {:error, :wrong_expected_version} ==
                 event_store.append_to_stream(event_store_meta, "stream", 2, build_events(1))

        assert :ok == event_store.append_to_stream(event_store_meta, "stream", 3, build_events(1))
      end
    end

    describe "stream events from an unknown stream" do
      test "should return stream not found error", %{
        event_store: event_store,
        event_store_meta: event_store_meta
      } do
        assert {:error, :stream_not_found} ==
                 event_store.stream_forward(event_store_meta, "unknownstream")
      end
    end

    describe "stream events from an existing stream" do
      test "should read events", %{event_store: event_store, event_store_meta: event_store_meta} do
        correlation_id = UUID.uuid4()
        causation_id = UUID.uuid4()
        events = build_events(4, correlation_id, causation_id)

        assert :ok == event_store.append_to_stream(event_store_meta, "stream", 0, events)

        read_events = event_store.stream_forward(event_store_meta, "stream") |> Enum.to_list()
        assert length(read_events) == 4
        assert coerce(events) == coerce(read_events)
        assert pluck(read_events, :stream_version) == [1, 2, 3, 4]

        Enum.each(read_events, fn event ->
          assert_is_uuid(event.event_id)
          assert event.stream_id == "stream"
          assert event.correlation_id == correlation_id
          assert event.causation_id == causation_id
          assert event.metadata == %{"metadata" => "value"}
          assert %DateTime{} = event.created_at
        end)

        read_events = event_store.stream_forward(event_store_meta, "stream", 3) |> Enum.to_list()
        assert coerce(Enum.slice(events, 2, 2)) == coerce(read_events)
        assert pluck(read_events, :stream_version) == [3, 4]
      end

      test "should read from single stream", %{
        event_store: event_store,
        event_store_meta: event_store_meta
      } do
        events1 = build_events(2)
        events2 = build_events(4)

        assert :ok == event_store.append_to_stream(event_store_meta, "stream", 0, events1)
        assert :ok == event_store.append_to_stream(event_store_meta, "secondstream", 0, events2)

        read_events = event_store.stream_forward(event_store_meta, "stream", 0) |> Enum.to_list()
        assert 2 == length(read_events)
        assert coerce(events1) == coerce(read_events)

        read_events =
          event_store.stream_forward(event_store_meta, "secondstream", 0) |> Enum.to_list()

        assert 4 == length(read_events)
        assert coerce(events2) == coerce(read_events)
      end

      test "should read events in batches", %{
        event_store: event_store,
        event_store_meta: event_store_meta
      } do
        events = build_events(10)

        assert :ok == event_store.append_to_stream(event_store_meta, "stream", 0, events)

        read_events =
          event_store.stream_forward(event_store_meta, "stream", 0, 2) |> Enum.to_list()

        assert length(read_events) == 10
        assert coerce(events) == coerce(read_events)

        assert pluck(read_events, :stream_version) == [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
      end
    end

    defp build_event(account_number, correlation_id, causation_id) do
      %EventData{
        correlation_id: correlation_id,
        causation_id: causation_id,
        event_type: "#{__MODULE__}.BankAccountOpened",
        data: %BankAccountOpened{account_number: account_number, initial_balance: 1_000},
        metadata: %{"metadata" => "value"}
      }
    end

    defp build_events(count, correlation_id \\ UUID.uuid4(), causation_id \\ UUID.uuid4())

    defp build_events(count, correlation_id, causation_id) do
      for account_number <- 1..count,
          do: build_event(account_number, correlation_id, causation_id)
    end

    defp assert_is_uuid(uuid) do
      assert uuid |> UUID.string_to_binary!() |> is_binary()
    end

    # Returns `true` if module implements behaviour.
    defp assert_implements(module, behaviour) do
      all = Keyword.take(module.__info__(:attributes), [:behaviour])

      assert [behaviour] in Keyword.values(all)
    end

    defp coerce(events) do
      Enum.map(
        events,
        &%{
          causation_id: &1.causation_id,
          correlation_id: &1.correlation_id,
          data: &1.data,
          metadata: &1.metadata
        }
      )
    end
  end
end
