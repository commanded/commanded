defmodule Event.UpcasterTest do
  use Commanded.StorageCase

  alias Commanded.EventStore
  alias Commanded.Event.Upcaster
  alias Commanded.EventStore.EventData

  defmodule EventOne do
    @derive Jason.Encoder
    defstruct(n: 0)
  end

  defmodule EventTwo do
    @derive Jason.Encoder
    defstruct(n: 10)

    defimpl Upcaster do
      def upcast(%{n: n} = event, _metadata), do: %{event | n: n * 2}
    end
  end

  test "will not upcast an event without an upcaster" do
    %{data: %{n: n}} =
      UUID.uuid4(:hex)
      |> write_event(struct(EventOne))
      |> read_event()

    assert n == 0
  end

  test "will upcast using defined upcaster" do
    %{data: %{n: n}} =
      UUID.uuid4(:hex)
      |> write_event(struct(EventTwo))
      |> read_event()

    assert n == 20
  end

  defp write_event(stream_uuid, %{__struct__: event_type} = data) do
    EventStore.append_to_stream(stream_uuid, :any_version, [
      %EventData{
        event_type: to_string(event_type),
        data: data,
        metadata: %{}
      }
    ])

    stream_uuid
  end

  defp read_event(stream_uuid) do
    EventStore.stream_forward(stream_uuid)
    |> Enum.into([])
    |> hd()
  end
end
