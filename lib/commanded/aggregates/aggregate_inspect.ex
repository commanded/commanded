alias Commanded.Aggregates.Aggregate

defimpl Inspect, for: Aggregate do
  import Inspect.Algebra

  def inspect(%Aggregate{} = aggregate, opts) do
    %Aggregate{
      aggregate_module: aggregate_module,
      aggregate_uuid: aggregate_uuid,
      aggregate_version: aggregate_version
    } = aggregate

    concat(["#", to_doc(aggregate_module, opts), "<#{aggregate_uuid}@#{aggregate_version}>"])
  end
end
