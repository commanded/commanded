defmodule Commanded.Event.Upcast.Events do
  alias Commanded.Event.Upcaster

  defmodule EventOne do
    @derive Jason.Encoder
    defstruct [:version, :reply_to, :process_id]
  end

  defmodule EventTwo do
    @derive Jason.Encoder
    defstruct [:version, :reply_to, :process_id]

    defimpl Upcaster do
      def upcast(%EventTwo{} = event, _metadata) do
        %EventTwo{event | version: 2}
      end
    end
  end

  defmodule EventThree do
    @derive Jason.Encoder
    defstruct [:version, :reply_to, :process_id]
  end

  defmodule EventFour do
    @derive Jason.Encoder
    defstruct [:version, :name, :reply_to, :process_id]
  end

  defmodule EventFive do
    @derive Jason.Encoder
    defstruct [:version, :reply_to, :process_id, :event_metadata]

    defimpl Upcaster do
      def upcast(%EventFive{} = event, metadata) do
        %EventFive{event | version: 2, event_metadata: metadata}
      end
    end
  end

  defimpl Upcaster, for: EventThree do
    def upcast(%EventThree{} = event, _metadata) do
      data = Map.from_struct(event) |> Map.put(:name, "Chris") |> Map.put(:version, 2)

      struct(EventFour, data)
    end
  end

  defmodule Stop do
    @derive Jason.Encoder
    defstruct [:process_id]
  end
end
