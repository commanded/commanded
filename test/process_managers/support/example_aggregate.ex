defmodule Commanded.ProcessManagers.ExampleAggregate do
  @moduledoc false
  alias Commanded.ProcessManagers.ExampleAggregate
  @derive Jason.Encoder
  defstruct uuid: nil,
            state: nil,
            items: []

  defmodule Commands do
    defmodule(Start, do: defstruct([:aggregate_uuid]))
    defmodule(Publish, do: defstruct([:aggregate_uuid, :interesting, :uninteresting]))
    defmodule(Pause, do: defstruct([:aggregate_uuid]))
    defmodule(Continue, do: defstruct([:aggregate_uuid]))
    defmodule(Stop, do: defstruct([:aggregate_uuid]))
    defmodule(Error, do: defstruct([:aggregate_uuid]))
    defmodule(Raise, do: defstruct([:aggregate_uuid]))
  end

  defmodule Events do
    defmodule Started do
      @derive Jason.Encoder
      defstruct([:aggregate_uuid])
    end

    defmodule Interested do
      @derive Jason.Encoder
      defstruct([:aggregate_uuid, :index])
    end

    defmodule Uninterested do
      @derive Jason.Encoder
      defstruct([:aggregate_uuid, :index])
    end

    defmodule Stopped do
      @derive Jason.Encoder
      defstruct([:aggregate_uuid])
    end

    defmodule Paused do
      @derive Jason.Encoder
      defstruct([:aggregate_uuid])
    end

    defmodule Errored do
      @derive Jason.Encoder
      defstruct([:aggregate_uuid])
    end

    defmodule Raised do
      @derive Jason.Encoder
      defstruct([:aggregate_uuid])
    end
  end

  def start(%ExampleAggregate{}, aggregate_uuid) do
    %Events.Started{aggregate_uuid: aggregate_uuid}
  end

  def publish(%ExampleAggregate{uuid: aggregate_uuid}, interesting, uninteresting) do
    Enum.concat(
      publish_interesting(aggregate_uuid, interesting, 1),
      publish_uninteresting(aggregate_uuid, uninteresting, 1)
    )
  end

  def pause(%ExampleAggregate{uuid: aggregate_uuid}) do
    %Events.Paused{aggregate_uuid: aggregate_uuid}
  end

  def stop(%ExampleAggregate{uuid: aggregate_uuid}) do
    %Events.Stopped{aggregate_uuid: aggregate_uuid}
  end

  def continue(%ExampleAggregate{}) do
    []
  end

  def error(%ExampleAggregate{uuid: aggregate_uuid}) do
    %Events.Errored{aggregate_uuid: aggregate_uuid}
  end

  def raise(%ExampleAggregate{uuid: aggregate_uuid}) do
    %Events.Raised{aggregate_uuid: aggregate_uuid}
  end

  defp publish_interesting(_aggregate_uuid, 0, _index), do: []

  defp publish_interesting(aggregate_uuid, interesting, index) do
    [
      %Events.Interested{aggregate_uuid: aggregate_uuid, index: index}
    ] ++ publish_interesting(aggregate_uuid, interesting - 1, index + 1)
  end

  defp publish_uninteresting(_aggregate_uuid, 0, _index), do: []

  defp publish_uninteresting(aggregate_uuid, interesting, index) do
    [
      %Events.Uninterested{aggregate_uuid: aggregate_uuid, index: index}
    ] ++ publish_uninteresting(aggregate_uuid, interesting - 1, index + 1)
  end

  # State mutators

  def apply(%ExampleAggregate{} = state, %Events.Started{aggregate_uuid: aggregate_uuid}),
    do: %ExampleAggregate{state | uuid: aggregate_uuid, state: :started}

  def apply(%ExampleAggregate{items: items} = state, %Events.Interested{index: index}),
    do: %ExampleAggregate{state | items: items ++ [index]}

  def apply(%ExampleAggregate{} = state, %Events.Paused{}),
    do: %ExampleAggregate{state | state: :paused}

  def apply(%ExampleAggregate{} = state, %Events.Errored{}),
    do: %ExampleAggregate{state | state: :errored}

  def apply(%ExampleAggregate{} = state, %Events.Raised{}),
    do: %ExampleAggregate{state | state: :exception}

  def apply(%ExampleAggregate{} = state, %Events.Uninterested{}), do: state

  def apply(%ExampleAggregate{} = state, %Events.Stopped{}),
    do: %ExampleAggregate{state | state: :stopped}
end
