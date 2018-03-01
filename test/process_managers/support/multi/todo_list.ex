defmodule Commanded.ProcessManagers.TodoList do
  @moduledoc false

  defstruct todo_uuids: []

  defmodule Commands do
    defmodule(CreateList, do: defstruct([:list_uuid, :todo_uuids]))
    defmodule(MarkAllDone, do: defstruct([:list_uuid]))
  end

  defmodule Events do
    defmodule(TodoListCreated, do: defstruct([:list_uuid, :todo_uuids]))
    defmodule(ListAllDone, do: defstruct([:list_uuid, :todo_uuids]))
  end

  alias Commanded.ProcessManagers.TodoList
  alias Commanded.ProcessManagers.TodoList.Commands.{CreateList, MarkAllDone}
  alias Commanded.ProcessManagers.TodoList.Events.{TodoListCreated, ListAllDone}

  def execute(%TodoList{}, %CreateList{list_uuid: list_uuid, todo_uuids: todo_uuids}) do
    %TodoListCreated{list_uuid: list_uuid, todo_uuids: todo_uuids}
  end

  def execute(%TodoList{todo_uuids: todo_uuids}, %MarkAllDone{list_uuid: list_uuid}) do
    %ListAllDone{list_uuid: list_uuid, todo_uuids: todo_uuids}
  end

  def apply(%TodoList{} = state, %TodoListCreated{todo_uuids: todo_uuids}),
    do: %TodoList{state | todo_uuids: todo_uuids}

  def apply(%TodoList{} = state, _event), do: state
end
