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
      defstruct [:account_number, :initial_balance]
    end

    setup %{application: application} do
      start_supervised!(application)

      :ok
    end

    describe "serializing events" do
      test "works with strict map", %{application: application} do
        stream_uuid = UUID.uuid4()

        event =
          %BankAccountOpened{
            :account_number => "1",
            :initial_balance => 1_000
          }
          |> IO.inspect()

        event_date = %EventData{
          causation_id: UUID.uuid4(),
          correlation_id: UUID.uuid4(),
          event_type: "#{__MODULE__}.BankAccountOpened",
          data: event,
          metadata: %{"user_id" => "test"}
        }

        assert :ok = EventStore.subscribe(application, stream_uuid)

        :ok = EventStore.append_to_stream(application, stream_uuid, 0, event_data)

        assert read_event =
                 EventStore.stream_forward(application, stream_uuid)
                 |> Enum.to_list()
                 |> List.first()
                 |> IO.inspect()
      end
    end
  end
end
