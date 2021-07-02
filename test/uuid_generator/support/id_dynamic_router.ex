defmodule Commanded.UUIDGenerator.IdAppDynamicRouter do
  use Commanded.Commands.Router

  alias Commanded.UUIDGenerator.IdMiddleware
  alias Commanded.UUIDGenerator.IdDynamicMiddleware
  alias Commanded.UUIDGenerator.Stuff
  alias Commanded.UUIDGenerator.Stuff.Commands.MakeStuff

  middleware(IdMiddleware)
  middleware(IdDynamicMiddleware)

  dispatch(MakeStuff, to: Stuff, identity: :stuff_id)
end
