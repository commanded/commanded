defmodule Commanded.Serialization.JsonSerializer.EventNameMapper do
  def to_name(_), do: nil
  def to_type(_), do: nil
end

defmodule Commanded.Serialization.JsonSerializer.EventName do

  alias Commanded.Serialization.JsonSerializer.EventNameMapper

  defmacro __using__(event_name) do
    event_names = Enum.filter(EventNameMapper.__info__(:attributes), &(:event_names == elem(&1, 0)))
    event_names = Enum.map(event_names, &(List.first(elem(&1, 1))))

    quote do
      event_names = unquote(event_names)
      event_name = unquote(event_name)
      
      content = quote do
	Module.register_attribute __MODULE__, :event_names, accumulate: true, persist: true
	for ev_name <- unquote(event_names) do
	    @event_names ev_name
	end
	@event_names {:"#{unquote(event_name)}", unquote(__MODULE__)}

	def to_name(module) do
	  case Enum.find(@event_names, &(module == elem(&1, 1))) do
	    nil -> nil
	    entry -> to_string(elem(entry, 0))
	  end
	end
	def to_type(event_name), do: Keyword.get(@event_names, :"#{event_name}")
      end

      ignore_module_conflict = Code.compiler_options[:ignore_module_conflict]
      Code.compiler_options(ignore_module_conflict: true)
      Module.create(EventNameMapper, content, Macro.Env.location(__ENV__))
      Code.compiler_options(ignore_module_conflict: ignore_module_conflict)
    end
  end
end

defmodule Commanded.Serialization.JsonSerializer do
  
  @moduledoc """
  A serializer that uses the JSON format.
  """

  @behaviour Commanded.EventStore.Serializer

  alias Commanded.Serialization.JsonDecoder
  alias Commanded.Serialization.JsonSerializer.EventNameMapper

  def to_event_name(module) do
    EventNameMapper.to_name(module) || Atom.to_string(module)
  end

  defp to_event_type(event_name) do
    (EventNameMapper.to_type(event_name) || event_name |> String.to_existing_atom) |> struct
  end

  @doc """
  Serialize given term to JSON binary data.
  """
  def serialize(term) do
    Poison.encode!(term)
  end

  @doc """
  Deserialize given JSON binary data to the expected type.
  """
  def deserialize(binary, config) do
    type = case Keyword.get(config, :type, nil) do
      nil -> nil
      type -> to_event_type(type)
    end

    binary
    |> Poison.decode!(as: type, keys: :atoms!)
    |> JsonDecoder.decode
  end
end
