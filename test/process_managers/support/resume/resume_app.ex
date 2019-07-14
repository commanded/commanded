defmodule Commanded.ProcessManagers.ResumeApp do
  @moduledoc false

  use Commanded.Application, otp_app: :commanded

  alias Commanded.ProcessManagers.ResumeRouter

  router(ResumeRouter)
end
