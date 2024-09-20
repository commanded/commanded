defmodule Commanded.Event.AfterStartHandler do
  use Commanded.Event.Handler,
    application: Commanded.MockedApp,
    name: __MODULE__

  def after_start(_state) do
    Process.send(:test, {:after_start, self()}, [])
  end
end
