defmodule Commanded.Middleware do
  alias Commanded.Middleware.Pipeline

  @type pipeline :: %Pipeline{}

  @callback before_dispatch(pipeline) :: pipeline
  @callback after_dispatch(pipeline) :: pipeline
  @callback after_failure(pipeline) :: pipeline
end
