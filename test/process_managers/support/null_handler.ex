defmodule Commanded.ProcessManagers.NullHandler do
  @moduledoc false
  @behaviour Commanded.Commands.Handler

  def handle(_aggregate, _command), do: []
end
