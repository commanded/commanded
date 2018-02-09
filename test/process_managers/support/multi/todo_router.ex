defmodule Commanded.ProcessManagers.TodoRouter do
  @moduledoc false

  use Commanded.Commands.Router

  alias Commanded.ProcessManagers.{Todo, TodoList}
  alias Commanded.ProcessManagers.Todo.Commands.{CreateTodo, MarkDone}
  alias Commanded.ProcessManagers.TodoList.Commands.{CreateList, MarkAllDone}

  identify Todo, by: :todo_uuid
  identify TodoList, by: :list_uuid

  dispatch [CreateTodo, MarkDone], to: Todo
  dispatch [CreateList, MarkAllDone], to: TodoList
end
