defmodule Commanded.ProcessManager.MultiRoutingTest do
  use ExUnit.Case

  import Commanded.Assertions.EventAssertions

  alias Commanded.ProcessManagers.ProcessRouter
  alias Commanded.ProcessManagers.{TodoApp, TodoProcessManager, TodoRouter}
  alias Commanded.ProcessManagers.Todo.Commands.CreateTodo
  alias Commanded.ProcessManagers.Todo.Events.TodoDone
  alias Commanded.ProcessManagers.TodoList.Commands.{CreateList, MarkAllDone}
  alias Commanded.ProcessManagers.TodoList.Events.ListAllDone

  setup do
    start_supervised!(TodoApp)

    :ok
  end

  test "should create process instance for each identifier returned by `interested?/2`" do
    {:ok, pm} = TodoProcessManager.start_link()

    todo1_uuid = create_todo()
    todo2_uuid = create_todo()
    todo3_uuid = create_todo()

    list_uuid = create_list_of_todos([todo1_uuid, todo2_uuid, todo3_uuid])

    # mark list done should mark individual TODOs as done via process manager
    :ok = TodoRouter.dispatch(%MarkAllDone{list_uuid: list_uuid}, application: TodoApp)

    assert_receive_event(TodoApp, ListAllDone, fn done -> assert done.list_uuid == list_uuid end)

    assert_receive_event(
      TodoApp,
      TodoDone,
      fn done -> done.todo_uuid == todo1_uuid end,
      fn done ->
        assert done.todo_uuid == todo1_uuid
      end
    )

    assert_receive_event(
      TodoApp,
      TodoDone,
      fn done -> done.todo_uuid == todo2_uuid end,
      fn done ->
        assert done.todo_uuid == todo2_uuid
      end
    )

    assert_receive_event(
      TodoApp,
      TodoDone,
      fn done -> done.todo_uuid == todo3_uuid end,
      fn done ->
        assert done.todo_uuid == todo3_uuid
      end
    )

    instances = ProcessRouter.process_instances(pm)
    assert length(instances) == 3
  end

  defp create_todo do
    todo_uuid = UUID.uuid4()
    command = %CreateTodo{todo_uuid: todo_uuid}

    :ok = TodoRouter.dispatch(command, application: TodoApp)

    todo_uuid
  end

  defp create_list_of_todos(todo_uuids) do
    list_uuid = UUID.uuid4()
    command = %CreateList{list_uuid: list_uuid, todo_uuids: todo_uuids}

    :ok = TodoRouter.dispatch(command, application: TodoApp)

    list_uuid
  end
end
