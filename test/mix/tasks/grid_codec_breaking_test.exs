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

  test "repeatable --schema-id checks multiple selected schemas", %{example_app_dir: dir} do
    repo_dir = Path.dirname(dir)
    events_path = Path.join(dir, "priv/schemas/events/schema.grid")
    risk_path = Path.join(dir, "priv/schemas/risk/schema.grid")

    File.write!(events_path, schema_with_struct("Events", 100))
    File.mkdir_p!(Path.dirname(risk_path))
    File.write!(risk_path, schema_with_struct("Risk", 200))
    commit_all!(repo_dir, "two schema baseline")

    File.write!(events_path, schema_without_struct("Events", 100))

    File.cd!(dir, fn ->
      output =
        capture_task(fn ->
          Breaking.run(["--schema-id", "200", "--against", "HEAD"])
        end)

      assert output =~ "No breaking changes detected."

      assert catch_exit(
               capture_task(fn ->
                 Breaking.run([
                   "--schema-id",
                   "100",
                   "--schema-id",
                   "200",
                   "--against",
                   "HEAD"
                 ])
               end)
             ) == {:shutdown, 1}
    end)
  end

  test "comma-separated schema IDs are accepted and missing IDs fail explicitly", %{
    example_app_dir: dir
  } do
    File.cd!(dir, fn ->
      output =
        capture_task(fn ->
          Breaking.run(["--schema-id", "100", "--against", "HEAD"])
        end)

      assert output =~ "No breaking changes detected."

      assert catch_exit(
               capture_task(fn ->
                 Breaking.run(["--schema-id", "100,999", "--against", "HEAD"])
               end)
             ) == {:shutdown, 2}
    end)
  end

  test "new selected schemas are reported and skipped without a wrapper script", %{
    example_app_dir: dir
  } do
    risk_path = Path.join(dir, "priv/schemas/risk/schema.grid")
    File.mkdir_p!(Path.dirname(risk_path))
    File.write!(risk_path, schema_without_struct("Risk", 200))

    File.cd!(dir, fn ->
      output =
        capture_task(fn ->
          Breaking.run([
            "--schema-id",
            "100",
            "--schema-id",
            "200",
            "--against",
            "HEAD"
          ])
        end)

      assert output =~ "Skipping priv/schemas/risk/schema.grid"
      assert output =~ "schema is new relative to HEAD"
      assert output =~ "No breaking changes detected."
    end)
  end

  test "task reports non-blocking documentation issues without failing", %{example_app_dir: dir} do
    schema_path = Path.join(dir, "priv/schemas/events/schema.grid")

    File.write!(schema_path, """
    @syntax 1

    schema Events {
      id: 100
      version: 1
    }

    struct Order (template_id: 1) {
      id: uuid_string
    }
    """)

    git!(Path.dirname(dir), ["add", "."])

    git!(Path.dirname(dir), [
      "-c",
      "user.name=GridCodec Tests",
      "-c",
      "user.email=tests@example.com",
      "commit",
      "-m",
      "baseline with struct"
    ])

    File.write!(schema_path, """
    @syntax 1

    schema Events {
      id: 100
      version: 1
    }

    struct Order (template_id: 1) {
      id: uuid_string, doc: "Stable identifier."
    }
    """)

    File.cd!(dir, fn ->
      output = capture_task(fn -> Breaking.run(["--against", "HEAD"]) end)
      assert output =~ "non-blocking issue"
      assert output =~ "DOC_FIELD_DOC_ADDED"
    end)
  end

  test "task reports appended variable fields as non-blocking info by default",
       %{example_app_dir: dir} do
    schema_path = Path.join(dir, "priv/schemas/events/schema.grid")

    File.write!(schema_path, """
    @syntax 1

    schema Events {
      id: 100
      version: 1
    }

    struct Order (template_id: 1) {
      id: uuid_string
    }
    """)

    git!(Path.dirname(dir), ["add", "."])

    git!(Path.dirname(dir), [
      "-c",
      "user.name=GridCodec Tests",
      "-c",
      "user.email=tests@example.com",
      "commit",
      "-m",
      "baseline with struct"
    ])

    File.write!(schema_path, """
    @syntax 1

    schema Events {
      id: 100
      version: 1
    }

    struct Order (template_id: 1, version: 2) {
      id: uuid_string
      note: string16, presence: optional, since: 2
    }
    """)

    File.cd!(dir, fn ->
      output = capture_task(fn -> Breaking.run(["--against", "HEAD"]) end)
      assert output =~ "non-blocking issue"
      assert output =~ "[info] [wire] WIRE_VAR_FIELD_ADDED"
    end)
  end

  test "task fails when policy escalates documentation issues", %{example_app_dir: dir} do
    schema_path = Path.join(dir, "priv/schemas/events/schema.grid")
    config_path = Path.join(dir, ".grid_codec.exs")

    File.write!(schema_path, """
    @syntax 1

    schema Events {
      id: 100
      version: 1
    }

    struct Order (template_id: 1) {
      id: uuid_string
    }
    """)

    git!(Path.dirname(dir), ["add", "."])

    git!(Path.dirname(dir), [
      "-c",
      "user.name=GridCodec Tests",
      "-c",
      "user.email=tests@example.com",
      "commit",
      "-m",
      "baseline with struct"
    ])

    File.write!(schema_path, """
    @syntax 1

    schema Events {
      id: 100
      version: 1
    }

    struct Order (template_id: 1) {
      id: uuid_string, doc: "Stable identifier."
    }
    """)

    File.write!(config_path, """
    [
      breaking: [
        schema_files: ["priv/schemas/**/*.grid"],
        against: "HEAD",
        severity_overrides: [DOC_FIELD_DOC_ADDED: :error]
      ]
    ]
    """)

    File.cd!(dir, fn ->
      assert catch_exit(capture_task(fn -> Breaking.run([]) end)) == {:shutdown, 1}
    end)
  end

  defp git!(cwd, args) do
    case System.cmd("git", args, cd: cwd, stderr_to_stdout: true) do
      {_output, 0} -> :ok
      {output, code} -> flunk("git #{Enum.join(args, " ")} failed with #{code}:\n#{output}")
    end
  end

  defp commit_all!(repo_dir, message) do
    git!(repo_dir, ["add", "."])

    git!(repo_dir, [
      "-c",
      "user.name=GridCodec Tests",
      "-c",
      "user.email=tests@example.com",
      "commit",
      "-m",
      message
    ])
  end

  defp schema_with_struct(name, id) do
    """
    @syntax 1

    schema #{name} {
      id: #{id}
      version: 1
    }

    struct Order (template_id: 1) {
      id: uuid_string
    }
    """
  end

  defp schema_without_struct(name, id) do
    """
    @syntax 1

    schema #{name} {
      id: #{id}
      version: 1
    }
    """
  end

  defp capture_task(fun) do
    ExUnit.CaptureIO.capture_io(fun)
  end
end
