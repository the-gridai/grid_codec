defmodule GridCodec.Breaking.ConfigTest do
  use ExUnit.Case, async: true

  alias GridCodec.Breaking.Config

  describe "defaults/0" do
    test "returns expected defaults" do
      defaults = Config.defaults()
      assert defaults.schema_files == ["priv/schemas/**/*.grid"]
      assert defaults.against == "origin/main"
      assert defaults.category == :source
      assert defaults.except == []
    end
  end

  describe "load/1" do
    test "returns defaults when no config file exists" do
      assert {:ok, config} = Config.load([])
      assert config.against == "origin/main"
      assert config.category == :source
    end

    test "CLI opts override defaults" do
      assert {:ok, config} = Config.load(against: "v1.0.0", category: "wire")
      assert config.against == "v1.0.0"
      assert config.category == :wire
    end

    test "returns error for missing explicit config file" do
      assert {:error, {:config_not_found, _}} =
               Config.load(config: "/nonexistent/.grid_codec.exs")
    end
  end
end
