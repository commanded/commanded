defmodule Commanded.Application do
  @moduledoc false
  use Application

  def start(_, _) do
    Commanded.Supervisor.start_link()
  end
end
