defmodule Commanded.ProcessManagers.TodoApp do
  use Commanded.Application, otp_app: :commanded

  alias Commanded.ProcessManagers.TodoRouter

  router(TodoRouter)
end
