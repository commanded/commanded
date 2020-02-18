defmodule Commanded.LocalRegistryTest do
  alias Commanded.Registration.LocalRegistry
  alias Commanded.RegistrationTestCase

  use RegistrationTestCase, registry: LocalRegistry

  setup do
    {:ok, child_spec, registry_meta} = LocalRegistry.child_spec(LocalRegistry, [])

    for child <- child_spec, do: start_supervised!(child)

    [registry_meta: registry_meta]
  end
end
