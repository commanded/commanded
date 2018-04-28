# Getting started

Commanded can be installed from hex as follows.

1. Add `commanded` to your list of dependencies in `mix.exs`:

    ```elixir
    def deps do
      [{:commanded, "~> 0.16"}]
    end
    ```

2. Fetch mix dependencies:

    ```console
    $ mix deps.get
    ```

3. Configure one of the supported event stores by following the "Choosing an Event Store" guide.

## Starting the Commanded application

The `commanded` application is automatically started for you once added to your application dependencies in `mix.exs`.
