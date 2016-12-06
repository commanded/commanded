defmodule Commanded.Storage.Extreme.Adapter do
  require Logger
  @moduledoc """ 
  Interface with the Extreme EventStore driver to save and read to EVENTSTORE.
  Note that the Engine supervisor starts the driver naming it as 'EventStore'.
  """
end
