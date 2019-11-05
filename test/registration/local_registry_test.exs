defmodule Commanded.LocalRegistryTest do
  alias Commanded.DefaultApp
  alias Commanded.RegistrationTestCase
  alias Commanded.Registration.LocalRegistry

  use RegistrationTestCase, application: DefaultApp, registry: LocalRegistry
end
