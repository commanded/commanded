# Getting started

Commanded can be installed from hex as follows.

1. Add `commanded` to your list of dependencies in `mix.exs`:

    ```elixir
    def deps do
      [{:commanded, "~> 0.17"}]
    end
    ```

2. Optionally add `poison` to make `Commanded.Serialization.JsonSerializer` available:

    ```elixir
    def deps do
      [{:poison, "~> 3.1 or ~> 4.0"}]
    end
    ```

3. Fetch mix dependencies:

    ```console
    $ mix deps.get
    ```

4. Configure one of the supported event stores by following the "Choosing an Event Store" guide.

## Starting the Commanded application

The `commanded` application is automatically started for you once added to your application dependencies in `mix.exs`.
