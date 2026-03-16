defmodule Mix.Tasks.GridCodec.BreakingTest do
  use ExUnit.Case, async: false

  alias GridCodec.Breaking.Checker
  alias Mix.Tasks.GridCodec.Breaking

  @schema """
  @syntax 1

  schema Events {
    id: 100
    version: 1
  }
  """

  setup do
    repo_dir =
      Path.join(
        System.tmp_dir!(),
        "grid_codec_breaking_task_#{System.unique_integer([:positive])}"
      )

    example_app_dir = Path.join(repo_dir, "example_app")
    schema_dir = Path.join(example_app_dir, "priv/schemas/events")

    File.mkdir_p!(schema_dir)
    File.write!(Path.join(schema_dir, "schema.grid"), @schema)

    git!(repo_dir, ["init"])
    git!(repo_dir, ["add", "."])

    git!(repo_dir, [
      "-c",
      "user.name=GridCodec Tests",
      "-c",
      "user.email=tests@example.com",
      "commit",
      "-m",
      "baseline"
    ])

    on_exit(fn -> File.rm_rf!(repo_dir) end)

    %{example_app_dir: example_app_dir}
  end

  test "baseline_from_git resolves paths from nested app directories", %{example_app_dir: dir} do
    File.cd!(dir, fn ->
      assert {:ok, content} = Checker.baseline_from_git("HEAD", "priv/schemas/events/schema.grid")
      assert content == @schema
    end)
  end

  test "task exits with code 2 when git baseline lookup errors", %{example_app_dir: dir} do
    File.cd!(dir, fn ->
      assert catch_exit(capture_task(fn -> Breaking.run(["--against", "missing-ref"]) end)) ==
               {:shutdown, 2}
    end)
  end

  defp git!(cwd, args) do
    case System.cmd("git", args, cd: cwd, stderr_to_stdout: true) do
      {_output, 0} -> :ok
      {output, code} -> flunk("git #{Enum.join(args, " ")} failed with #{code}:\n#{output}")
    end
  end

  defp capture_task(fun) do
    ExUnit.CaptureIO.capture_io(fun)
  end
end
