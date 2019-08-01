# Getting started

Commanded can be installed from hex as follows.

1. Add `commanded` to your list of dependencies in `mix.exs`:

    ```elixir
    def deps do
      [{:commanded, "~> 0.19"}]
    end
    ```

2. Optionally add `jason` to make `Commanded.Serialization.JsonSerializer` available:

    ```elixir
    def deps do
      [{:jason, "~> 1.1"}]
    end
    ```

3. Fetch mix dependencies:

    ```console
    $ mix deps.get
    ```

4. Define a Commanded application module for your app, see the "Application" guide for details.

    ```elixir
    defmodule MyApp.Application do
      use Commanded.Application, otp_app: :my_app
    end
    ```

5. Configure one of the supported event stores by following the "Choosing an Event Store" guide.
