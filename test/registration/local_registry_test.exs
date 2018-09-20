defmodule Commanded.LocalRegistryTest do
  alias Commanded.RegistrationTestCase
  alias Commanded.Registration.LocalRegistry

  use RegistrationTestCase, registry: LocalRegistry
end
