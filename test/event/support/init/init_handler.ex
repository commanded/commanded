defmodule Commanded.Event.InitHandler do
  use Commanded.Event.Handler,
    application: Commanded.MockedApp,
    name: __MODULE__

  def init do
    Process.send(:test, {:init, self()}, [])
  end
end
