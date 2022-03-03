defmodule Commanded.ProcessManagers.TodoList do
  @moduledoc false
  @derive Jason.Encoder
  defstruct todo_uuids: []

  defmodule Commands do
    defmodule CreateList do
      @derive Jason.Encoder
      defstruct([:list_uuid, :todo_uuids])
    end

    defmodule MarkAllDone do
      @derive Jason.Encoder
      defstruct([:list_uuid])
    end
  end

  defmodule Events do
    defmodule TodoListCreated do
      @derive Jason.Encoder
      defstruct([:list_uuid, :todo_uuids])
    end

    defmodule ListAllDone do
      @derive Jason.Encoder
      defstruct([:list_uuid, :todo_uuids])
    end
  end

  alias Commanded.ProcessManagers.TodoList
  alias Commanded.ProcessManagers.TodoList.Commands.{CreateList, MarkAllDone}
  alias Commanded.ProcessManagers.TodoList.Events.{ListAllDone, TodoListCreated}

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
