defmodule Commanded.UUIDGenerator.IdAppRouter do
  use Commanded.Commands.Router

  alias Commanded.UUIDGenerator.IdMiddleware

  alias Commanded.UUIDGenerator.Stuff
  alias Commanded.UUIDGenerator.Stuff.Commands.MakeStuff

  middleware(IdMiddleware)

  dispatch(MakeStuff, to: Stuff, identity: :stuff_id)
end
