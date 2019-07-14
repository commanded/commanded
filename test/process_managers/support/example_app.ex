defmodule Commanded.ProcessManagers.ExampleApp do
  @moduledoc false

  use Commanded.Application, otp_app: :commanded

  alias Commanded.ProcessManagers.ExampleRouter

  router(ExampleRouter)
end
