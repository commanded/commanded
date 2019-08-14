defprotocol Commanded.Event.Upcaster do
  @moduledoc """
  Protocol to allow an event to be transformed before being passed to a
  consumer.

  You can use an upcaster to change the shape of an event
  (e.g. add a new field with a default, rename a field) or rename an event.

  Because the upcaster changes any historical event to the latest version,
  consumers (aggregates, event handlers, and process managers) only need
  to support the latest version.

  ## Example

      defimpl Commanded.Event.Upcaster, for: AnEvent do
        def upcast(%AnEvent{} = event, _metadata) do
          %AnEvent{name: name} = event

          %AnEvent{event | first_name: name}
        end
      end
      
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
