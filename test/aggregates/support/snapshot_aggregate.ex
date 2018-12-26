defmodule Commanded.Aggregates.SnapshotAggregate do
  @moduledoc false
  @derive Jason.Encoder
  defstruct [
    :name,
    :date
  ]

  defmodule Commands do
    defmodule(Create, do: defstruct([:name, :date]))
  end

  defmodule Events do
    defmodule Created do
      @derive Jason.Encoder
      defstruct([:name, :date])
    end
  end

  alias Commanded.Aggregates.SnapshotAggregate
  alias Commands.Create
  alias Events.Created

  def execute(
        %SnapshotAggregate{name: nil},
        %Create{name: name, date: date}
      ) do
    %Created{name: name, date: date}
  end

  # State mutators

  def apply(
        %SnapshotAggregate{} = state,
        %Created{name: name, date: date}
      ) do
    %SnapshotAggregate{state | name: name, date: date}
  end
end

alias Commanded.Aggregates.SnapshotAggregate

defimpl Commanded.Serialization.JsonDecoder, for: SnapshotAggregate do
  @doc """
  Parse the date included in the aggregate state
  """
  def decode(%SnapshotAggregate{date: date} = state) do
    %SnapshotAggregate{state | date: NaiveDateTime.from_iso8601!(date)}
  end
end
