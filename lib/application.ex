defmodule Commanded.Application do
  use Application

  def start(_, _) do
    Commanded.Supervisor.start_link
  end
end
