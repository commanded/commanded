defmodule Commanded.Commands.Composite.CompositeCompositeRouter do
  @moduledoc false

  use Commanded.Commands.CompositeRouter

  alias Commanded.Commands.Composite.ExampleCompositeRouter

  router(ExampleCompositeRouter)
end
