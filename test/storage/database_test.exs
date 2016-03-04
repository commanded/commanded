defmodule EventStore.Storage.DatabaseTest do
  use ExUnit.Case
  doctest EventStore.Storage.Database

  alias EventStore.Storage
  alias EventStore.Storage.Database

  def temp_database_config do
    config = Application.get_env(:eventstore, Storage)
    Keyword.merge(config, [database: config[:database] <> "_temp"])
  end

  def create_database do
    Database.create(temp_database_config)
  end

  def drop_database do
    Database.drop(temp_database_config)
  end

  setup do
    on_exit fn -> drop_database end
    :ok
  end

  test "create database when already exists" do
    assert create_database == :ok
    assert create_database == {:error, :already_up}
  end

  test "drop database when already dropped" do
    create_database

    assert drop_database == :ok
    assert drop_database == {:error, :already_down}
  end
end
