defmodule Commanded.ProcessManagers.TodoProcessManager do
  @moduledoc false

  alias Commanded.ProcessManagers.{TodoRouter, TodoProcessManager}

  use Commanded.ProcessManagers.ProcessManager,
    name: __MODULE__,
    router: TodoRouter

  @derive Jason.Encoder
  defstruct [:todo_uuid]

  alias Commanded.ProcessManagers.Todo.Events.TodoCreated
  alias Commanded.ProcessManagers.TodoList.Events.ListAllDone
  alias Commanded.ProcessManagers.Todo.Commands.MarkDone

  def interested?(%TodoCreated{todo_uuid: todo_uuid}), do: {:start, todo_uuid}
  def interested?(%ListAllDone{todo_uuids: todo_uuids}), do: {:continue, todo_uuids}

  def handle(%TodoProcessManager{}, %TodoCreated{}), do: []

  def handle(%TodoProcessManager{todo_uuid: todo_uuid}, %ListAllDone{}) do
    %MarkDone{todo_uuid: todo_uuid}
  end

  def apply(%TodoProcessManager{} = state, %TodoCreated{todo_uuid: todo_uuid}) do
    %TodoProcessManager{state | todo_uuid: todo_uuid}
  end

  def apply(%TodoProcessManager{} = state, _event), do: state
end
