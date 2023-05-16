defprotocol Commanded.Event.Upcaster do
  @moduledoc """
  Protocol to allow an event to be transformed before being passed to a
  consumer.

  You can use an upcaster to change the shape of an event (e.g. add a new field
  with a default, rename a field) or rename an event.

  Upcaster will run for new events and for historical events.

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

  ## Metadata

  The `upcast/2` function receives the domain event and a map of metadata
  associated with that event. The metadata is provided during command dispatch.

  In addition to the metadata key/values you provide, the following system
  values will be included in the metadata:

    - `application` - the `Commanded.Application` used to read the event.
    - `event_id` - a globally unique UUID to identify the event.
    - `event_number` - a globally unique, monotonically incrementing integer
      used to order the event amongst all events.
    - `stream_id` - the stream identity for the event.
    - `stream_version` - the version of the stream for the event.
    - `causation_id` - an optional UUID identifier used to identify which
      command caused the event.
    - `correlation_id` - an optional UUID identifier used to correlate related
      commands/events.
    - `created_at` - the datetime, in UTC, indicating when the event was
      created.

  These key/value metadata pairs will use atom keys to differentiate them from
  the user provided metadata which uses string keys.

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
