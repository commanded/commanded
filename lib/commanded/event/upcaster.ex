defprotocol Commanded.Event.Upcaster do
  @fallback_to_any true

  @spec upcast(event :: struct(), metadata :: struct()) :: struct()
  def upcast(event, metadata)
end

defimpl Commanded.Event.Upcaster, for: Any do
  def upcast(event, _metadata), do: event
end
