# Read model projections

Your read model can be built using a Commanded event handler and whichever storage provider you prefer. You can choose to use a SQL or NoSQL database, document store, the filesystem, a full text search index, or any other storage mechanism. You may even use multiple storage providers, optimised for the querying they must support.

## Ecto projections

You can use the [Commanded Ecto projections](https://github.com/slashdotdash/commanded-ecto-projections) library to build a read model using one of the databases supported by Ecto (PostgreSQL, MySQL, et al).

### Example

```elixir
defmodule MyApp.ExampleProjector do
  use Commanded.Projections.Ecto, name: "ExampleProjector"

  project %AnEvent{name: name}, _metadata do
    Ecto.Multi.insert(multi, :example_projection, %ExampleProjection{name: name})
  end

  project %AnotherEvent{name: name} do
    Ecto.Multi.insert(multi, :example_projection, %ExampleProjection{name: name})
  end
end
```
