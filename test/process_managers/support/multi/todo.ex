defmodule Commanded.ProcessManagers.Todo do
  @moduledoc false

  @derive Jason.Encoder
  defstruct status: nil

  defmodule Commands do
    defmodule CreateTodo do
      @derive Jason.Encoder
      defstruct([:todo_uuid])
    end

    defmodule MarkDone do
      @derive Jason.Encoder
      defstruct([:todo_uuid])
    end
  end

  defmodule Events do
    defmodule TodoCreated do
      @derive Jason.Encoder
      defstruct([:todo_uuid])
    end

    defmodule TodoDone do
      @derive Jason.Encoder
      defstruct([:todo_uuid])
    end
  end

  alias Commanded.ProcessManagers.Todo
  alias Commanded.ProcessManagers.Todo.Commands.{CreateTodo, MarkDone}
  alias Commanded.ProcessManagers.Todo.Events.{TodoCreated, TodoDone}

  def execute(%Todo{}, %CreateTodo{todo_uuid: todo_uuid}) do
    %TodoCreated{todo_uuid: todo_uuid}
  end

  def execute(%Todo{}, %MarkDone{todo_uuid: todo_uuid}) do
    %TodoDone{todo_uuid: todo_uuid}
  end

  # State mutators

  def apply(%Todo{} = state, %TodoCreated{}), do: %Todo{state | status: :pending}

  def apply(%Todo{} = state, %TodoDone{}), do: %Todo{state | status: :done}
end
