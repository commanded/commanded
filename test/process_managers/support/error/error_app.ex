defmodule Commanded.ProcessManagers.ErrorApp do
  @moduledoc false

  use Commanded.Application, otp_app: :commanded

  alias Commanded.ProcessManagers.ErrorRouter

  router(ErrorRouter)
end
