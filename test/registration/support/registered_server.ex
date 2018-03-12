defmodule Commanded.Registration.RegisteredServer do
  use GenServer
  use Commanded.Registration

  def start_link(name, opts \\ []) do
    GenServer.start_link(__MODULE__, name, opts)
  end

  def init(name), do: {:ok, name}
end
