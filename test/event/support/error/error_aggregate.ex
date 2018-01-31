defmodule Commanded.Event.ErrorAggregate do
  @moduledoc false

  defstruct [:uuid]

  defmodule Commands do
    defmodule(RaiseError, do: defstruct([:uuid, :strategy, :delay, :reply_to]))
  end

  defmodule Events do
    defmodule(ErrorEvent, do: defstruct([:uuid, :strategy, :delay, :reply_to]))
  end

  alias Commanded.Event.ErrorAggregate
  alias Commands.RaiseError
  alias Events.ErrorEvent

  def execute(%ErrorAggregate{}, %RaiseError{} = raise_error) do
    struct(ErrorEvent, Map.from_struct(raise_error))
  end

  def apply(%ErrorAggregate{} = aggregate, %ErrorEvent{uuid: uuid}),
    do: %ErrorAggregate{aggregate | uuid: uuid}
end
