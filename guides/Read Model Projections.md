# Read model projections

Your read model can be built using a Commanded event handler and whichever storage provider you prefer. You can choose to use a SQL or NoSQL database, document store, the filesystem, a full text search index, or any other storage mechanism. You may even use multiple storage providers, optimised for the querying they must support.

## Ecto projections

You can use the [Commanded Ecto projections](https://github.com/commanded/commanded-ecto-projections) library to build a read model using one of the databases supported by Ecto (PostgreSQL, MySQL, et al).

### Example

```elixir
defmodule MyApp.ExampleProjector do
  use Commanded.Projections.Ecto,
    application: MyApp.ExampleApp,
    name: "ExampleProjector"

  project %AnEvent{name: name}, _metadata do
    Ecto.Multi.insert(multi, :example_projection, %ExampleProjection{name: name})
  end

  project %AnotherEvent{name: name} do
    Ecto.Multi.insert(multi, :example_projection, %ExampleProjection{name: name})
  end
end
```

## Consistency guarantee

You will often choose to use `:strong` consistency for read model projections to ensure that you can query data affected by a dispatched command. In a typical web request using the [POST/Redirect/GET](https://en.wikipedia.org/wiki/Post/Redirect/Get) pattern you want to ensure the read model is up-to-date before redirecting the user to the modified resource.

By opting in to strong consistency you are guaranteed that an `:ok` reply from command dispatch indicates all strongly consistent read models will have been updated.

Configure the `consistency` option in your projector:

```elixir
defmodule MyApp.ExampleProjector do
  use Commanded.Projections.Ecto,
    application: MyApp.ExampleApp,
    name: "ExampleProjector",
    consistency: :strong
end
```
