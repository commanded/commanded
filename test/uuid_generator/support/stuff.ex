defmodule Commanded.UUIDGenerator.Stuff do
  defmodule Commands do
    defmodule MakeStuff do
      @enforce_keys [:stuff_id, :name]
      defstruct [:stuff_id, :name]
    end
  end

  defmodule Events do
    defmodule StuffMade do
      @derive Jason.Encoder
      defstruct [:stuff_id, :name]
    end
  end

  alias Commanded.UUIDGenerator.Stuff
  alias Commanded.UUIDGenerator.Stuff.Commands.MakeStuff
  alias Commanded.UUIDGenerator.Stuff.Events.StuffMade

  defstruct [:stuff_id, :name]

  def execute(%Stuff{stuff_id: nil}, %MakeStuff{} = command) do
    %MakeStuff{stuff_id: stuff_id, name: name} = command

    %StuffMade{stuff_id: stuff_id, name: name}
  end

  def apply(%Stuff{} = stuff, %StuffMade{} = event) do
    %StuffMade{stuff_id: stuff_id, name: name} = event

    %Stuff{stuff | stuff_id: stuff_id, name: name}
  end
end
