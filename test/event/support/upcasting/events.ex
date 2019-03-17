defmodule Commanded.Event.Upcasting.Events do
  alias Commanded.Event.Upcaster

  defmodule EventOne do
    @derive Jason.Encoder
    defstruct [:n, :reply_to, :process_id]
  end

  defmodule EventTwo do
    @derive Jason.Encoder
    defstruct [:n, :reply_to, :process_id]

    defimpl Upcaster do
      def upcast(%{n: n} = event, _metadata), do: %{event | n: n * 2}
    end
  end

  defmodule EventThree do
    @derive Jason.Encoder
    defstruct [:n, :reply_to, :process_id]
  end

  defmodule EventFour do
    @derive Jason.Encoder
    defstruct [:n, :name, :reply_to, :process_id]

    defimpl Upcaster, for: EventThree do
      def upcast(event, _metadata) do
        data = Map.from_struct(event) |> Map.put(:name, "Chris")
        struct(EventFour, data)
      end
    end
  end

  defmodule Stop do
    @derive Jason.Encoder
    defstruct [:process_id]
  end
end
