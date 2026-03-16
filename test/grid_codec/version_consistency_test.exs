defmodule GridCodec.VersionConsistencyTest do
  use ExUnit.Case, async: true

  @version Mix.Project.config()[:version]

  describe "README.md" do
    test "installation tag matches mix.exs version" do
      readme = File.read!(Path.join(__DIR__, "../../README.md"))

      case Regex.run(~r/tag:\s*"v([^"]+)"/, readme) do
        [_, tag_version] ->
          assert tag_version == @version,
                 """
                 README.md installation tag is v#{tag_version} but mix.exs version is #{@version}.
                 Update the tag in README.md:

                     {:grid_codec, git: "...", tag: "v#{@version}"}
                 """

        nil ->
          flunk("No tag: \"v...\" found in README.md installation section")
      end
    end
  end

  describe "CHANGELOG.md" do
    test "has entry for current version or [Unreleased]" do
      changelog = File.read!(Path.join(__DIR__, "../../CHANGELOG.md"))

      has_version_entry = String.contains?(changelog, "[#{@version}]")
      has_unreleased = String.contains?(changelog, "[Unreleased]")

      assert has_version_entry or has_unreleased,
             """
             CHANGELOG.md has no entry for version #{@version} and no [Unreleased] section.
             Add a changelog entry before releasing.
             """
    end
  end
end
