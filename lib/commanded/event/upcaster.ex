defprotocol Commanded.Event.Upcaster do
  @fallback_to_any true

  @spec upcast(event :: struct()) :: struct()
  def upcast(event)
end

defimpl Commanded.Event.Upcaster, for: Any do
  def upcast(event), do: event
end
