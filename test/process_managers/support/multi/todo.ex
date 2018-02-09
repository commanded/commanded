defmodule Commanded.ProcessManagers.Todo do
  @moduledoc false

  defstruct status: nil

  defmodule Commands do
    defmodule(CreateTodo, do: defstruct([:todo_uuid]))
    defmodule(MarkDone, do: defstruct([:todo_uuid]))
  end

  defmodule Events do
    defmodule(TodoCreated, do: defstruct([:todo_uuid]))
    defmodule(TodoDone, do: defstruct([:todo_uuid]))
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

  # state mutatators

  def apply(%Todo{} = state, %TodoCreated{}), do: %Todo{state | status: :pending}

  def apply(%Todo{} = state, %TodoDone{}), do: %Todo{state | status: :done}
end
