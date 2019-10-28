defmodule Commanded.EventStore.SerializationCase do
  import Commanded.SharedTestCase

  define_tests do
    alias Commanded.EventStore
    alias Commanded.EventStore.EventData
    alias Commanded.EventStore.Subscriber
    alias Commanded.EventStore.RecordedEvent
    alias Commanded.Helpers.ProcessHelper

    defmodule BankAccountOpened do
      @derive Jason.Encoder
      defstruct [:account_number, :initial_balance, :purpose]
    end

    setup %{adapter: adapter} do
      config = [
        name: UUID.uuid4(),
        serializer: Commanded.Serialization.JsonSerializer
      ]

      %{adapter: adapter, config: config}
    end

    describe "serializing events" do
      test "should work with no specified encoding_options", %{adapter: adapter, config: config} do
        config = config |> Keyword.put_new(:encoding_options, %{})

        start_adapter(adapter, config)

        events =
          %BankAccountOpened{}
          |> build_event("#{__MODULE__}.BankAccountOpened")
          |> List.wrap()

        assert :ok =
                 adapter.append_to_stream(
                   {adapter, config},
                   "stream",
                   0,
                   events
                 )
      end

      test "should be able to specify an escape option", %{adapter: adapter, config: config} do
        config = config |> Keyword.put_new(:encoding_options, %{escape: :unicode})

        adapter_pid = start_adapter(adapter, config)

        events =
          %BankAccountOpened{purpose: "A reasonable pürpose with a unicode"}
          |> build_event("#{__MODULE__}.BankAccountOpened")
          |> List.wrap()

        assert :ok =
                 adapter.append_to_stream(
                   {adapter, config},
                   "stream",
                   0,
                   events
                 )

        %RecordedEvent{data: data} = adapter_pid |> pluck_first_event_from_stream()

        assert data =~ "p\\u00FCrpose"
      end

      test "should be able to specify a map option", %{adapter: adapter, config: config} do
        config = config |> Keyword.put_new(:encoding_options, %{maps: :strict})

        start_adapter(adapter, config)

        events =
          %{:important_property => 1_000, "important_property" => 2_000}
          |> build_event("#{__MODULE__}.BankAccountOpened")
          |> List.wrap()

        error = append_to_stream_and_catch_exit(adapter, config, events)

        assert %Jason.EncodeError{message: message} = error
        assert message =~ "duplicate key"
      end
    end

    describe "decoding_options" do
      test "should be able to specify key options", %{adapter: adapter, config: config} do
        expected_value = "expected to change to string"
        config = config |> Keyword.put_new(:decoding_options, %{keys: :strings})

        adapter_pid = start_adapter(adapter, config)

        events =
          %{originally_atom: expected_value}
          |> build_event(nil)
          |> List.wrap()

        assert :ok =
                 adapter.append_to_stream(
                   {adapter, config},
                   "stream",
                   0,
                   events
                 )

        %RecordedEvent{data: data} =
          adapter.stream_forward({adapter, config}, "stream", 0) |> List.first()

        assert %{"originally_atom" => ^expected_value} = data
      end
    end

    defp append_to_stream_and_catch_exit(adapter, config, events, stream \\ "stream") do
      result =
        catch_exit(
          adapter.append_to_stream(
            {adapter, config},
            stream,
            0,
            events
          )
        )

      assert {{error, _stack}, _function_call} = result
      error
    end

    defp start_adapter(adapter, config) do
      for child <- adapter.child_spec(adapter, config) do
        start_supervised!(child)
      end

      Process.whereis(adapter)
    end

    defp build_event(data, type) do
      %EventData{
        causation_id: UUID.uuid4(),
        correlation_id: UUID.uuid4(),
        event_type: type,
        data: data
      }
    end

    defp pluck_first_event_from_stream(pid, stream \\ "stream") do
      %RecordedEvent{} =
        pid
        |> :sys.get_state()
        |> Map.get(:streams)
        |> Map.get(stream)
        |> List.first()
    end
  end
end
