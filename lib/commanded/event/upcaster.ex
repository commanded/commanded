defprotocol Commanded.Event.Upcaster do
  @doc """
  Protocol to allow an event to be transformed before being passed to a
  consumer.

  You can use an upcaster to change the shape of an event
  (e.g. add a new field with a default, rename a field).

  Because the upcaster changes any historical event to the latest version,
  consumers (aggregates, event handlers, and process managers) only need
  to support the latest version.
  """

  @fallback_to_any true
  @spec upcast(event :: struct(), metadata :: map()) :: struct()
  def upcast(event, metadata)
end

defimpl Commanded.Event.Upcaster, for: Any do
  @moduledoc """
  The default implementation of the `Commanded.Event.Upcaster`.

  This will return an event unchanged.
  """

  def upcast(event, _metadata), do: event
end
