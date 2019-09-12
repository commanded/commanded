defmodule Commanded.Aggregates.SnapshotAggregate do
  @moduledoc false
  @derive Jason.Encoder
  defstruct [:name, :datetime]

  defmodule Commands do
    defmodule Create do
      defstruct [:name, :datetime]
    end
  end

  defmodule Events do
    defmodule Created do
      @derive Jason.Encoder
      defstruct [:name, :datetime]
    end
  end

  alias Commanded.Aggregates.SnapshotAggregate
  alias Commands.Create
  alias Events.Created

  # Command functions

  def execute(%SnapshotAggregate{name: nil}, %Create{} = command) do
    %Create{name: name, datetime: datetime} = command

    %Created{name: name, datetime: datetime}
  end

  # State mutators

  def apply(%SnapshotAggregate{} = state, %Created{} = event) do
    %Created{name: name, datetime: datetime} = event

    %SnapshotAggregate{state | name: name, datetime: datetime}
  end
end

alias Commanded.Aggregates.SnapshotAggregate

defimpl Commanded.Serialization.JsonDecoder, for: SnapshotAggregate do
  @doc """
  Parse the datetime included in the aggregate state
  """
  def decode(%SnapshotAggregate{} = state) do
    %SnapshotAggregate{datetime: datetime} = state

    {:ok, dt, _} = DateTime.from_iso8601(datetime)

    %SnapshotAggregate{state | datetime: dt}
  end
end
