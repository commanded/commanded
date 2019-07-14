defmodule Commanded.Commands.ConsistencyApp do
  use Commanded.Application, otp_app: :commanded

  alias Commanded.Commands.ConsistencyRouter

  router(ConsistencyRouter)
end
