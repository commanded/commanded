# Getting started

Commanded can be installed from the package manager hex as follows.

1. Add `commanded` to your list of dependencies in `mix.exs`:

    ```elixir
    def deps do
      [{:commanded, "~> 1.4"}]
    end
    ```

2. Optionally add `jason` to support JSON serialization via `Commanded.Serialization.JsonSerializer`:

    ```elixir
    def deps do
      [{:jason, "~> 1.3"}]
    end
    ```

3. Fetch mix dependencies:

    ```console
    $ mix deps.get
    ```

4. Define a Commanded application module for your app, see the [Application guide](https://hexdocs.pm/commanded/application.html) for details.

    ```elixir
    defmodule MyApp.Application do
      use Commanded.Application, otp_app: :my_app
    end
    ```

5. Configure one of the supported event stores by following the [Choosing an Event Store guide](https://hexdocs.pm/commanded/choosing-an-event-store.html).
