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
      assert defaults.include_docs == true
      assert defaults.fail_on == [:error]
      assert defaults.severity_overrides == %{}
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

    test "loads docs policy from config file" do
      dir =
        Path.join(System.tmp_dir!(), "grid_codec_config_#{System.unique_integer([:positive])}")

      File.mkdir_p!(dir)
      config_path = Path.join(dir, ".grid_codec.exs")
      on_exit(fn -> File.rm_rf(dir) end)

      File.write!(config_path, """
      [
        breaking: [
          include_docs: false,
          fail_on: [:error, :warning],
          severity_overrides: [DOC_FIELD_DOC_CHANGED: :error]
        ]
      ]
      """)

      assert {:ok, config} = Config.load(config: config_path)
      assert config.include_docs == false
      assert config.fail_on == [:error, :warning]
      assert config.severity_overrides == %{DOC_FIELD_DOC_CHANGED: :error}
    end

    test "returns error for missing explicit config file" do
      assert {:error, {:config_not_found, _}} =
               Config.load(config: "/nonexistent/.grid_codec.exs")
    end
  end
end
