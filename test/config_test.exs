defmodule EventStore.ConfigTest do
  use ExUnit.Case

  alias EventStore.Config

  test "parse keys" do
    original = [
      username: "postgres",
      password: "postgres",
      database: "eventstore_test",
      hostname: "localhost"
    ]

    config = Config.parse original
    assert config == original
  end

  test "parse url" do
    original = [ url: "postgres://username:password@localhost/database" ]

    config = Config.parse original
    assert config == [
      username: "username",
      password: "password",
      database: "database",
      hostname: "localhost"
    ]
  end
end
