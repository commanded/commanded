defmodule Commanded.Aggregates.SnapshotAggregate do
  @moduledoc false
  @derive Jason.Encoder
  defstruct [:name, :date]

  defmodule Commands do
    defmodule Create do
      defstruct [:name, :date]
    end
  end

  defmodule Events do
    defmodule Created do
      @derive Jason.Encoder
      defstruct [:name, :date]
    end
  end

  alias Commanded.Aggregates.SnapshotAggregate
  alias Commands.Create
  alias Events.Created

  # Command functions

  def execute(%SnapshotAggregate{name: nil}, %Create{} = command) do
    %Create{name: name, date: date} = command

    %Created{name: name, date: date}
  end

  # State mutators

  def apply(%SnapshotAggregate{} = state, %Created{} = event) do
    %Created{name: name, date: date} = event

    %SnapshotAggregate{state | name: name, date: date}
  end
end

alias Commanded.Aggregates.SnapshotAggregate

defimpl Commanded.Serialization.JsonDecoder, for: SnapshotAggregate do
  @doc """
  Parse the date included in the aggregate state
  """
  def decode(%SnapshotAggregate{} = state) do
    %SnapshotAggregate{date: date} = state

    %SnapshotAggregate{state | date: NaiveDateTime.from_iso8601!(date)}
  end
end
