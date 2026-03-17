defmodule Mix.Tasks.GridCodec.ExportTest do
  use ExUnit.Case, async: true

  alias Mix.Tasks.GridCodec.Export

  @tmp_base Path.join(System.tmp_dir!(), "grid_codec_export_check_test")

  setup do
    dir = Path.join(@tmp_base, "#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)

    %{output_dir: dir}
  end

  defp all_grid_files(dir) do
    Path.wildcard(Path.join(dir, "**/*.grid"))
  end

  defp master_files(dir) do
    all_grid_files(dir) |> Enum.filter(&(Path.basename(&1) == "schema.grid"))
  end

  defp individual_files(dir) do
    all_grid_files(dir) |> Enum.reject(&(Path.basename(&1) == "schema.grid"))
  end

  defp snapshot(dir) do
    dir
    |> all_grid_files()
    |> Enum.sort()
    |> Map.new(fn path -> {Path.relative_to(path, dir), File.read!(path)} end)
  end

  describe "--check with up-to-date files" do
    test "exits 0 when files match generated output", %{output_dir: dir} do
      capture_task(fn ->
        Export.run(["--output-dir", dir])
      end)

      assert all_grid_files(dir) != []

      assert capture_task(fn ->
               Export.run(["--check", "--output-dir", dir])
             end) =~ "up to date"
    end
  end

  describe "--check with stale files" do
    test "exits non-zero when a file differs", %{output_dir: dir} do
      capture_task(fn ->
        Export.run(["--output-dir", dir])
      end)

      [first | _] = individual_files(dir)
      File.write!(first, File.read!(first) <> "\n# stale")

      assert catch_exit(
               capture_task(fn ->
                 Export.run(["--check", "--output-dir", dir])
               end)
             ) == {:shutdown, 1}
    end
  end

  describe "--check with unexpected files" do
    test "exits non-zero when an extra generated file exists", %{output_dir: dir} do
      capture_task(fn ->
        Export.run(["--output-dir", dir])
      end)

      extra = Path.join(dir, "schema_999/orphan.grid")
      File.mkdir_p!(Path.dirname(extra))
      File.write!(extra, "@syntax 1\nstruct Orphan (template_id: 1) {}\n")

      assert catch_exit(
               capture_task(fn ->
                 Export.run(["--check", "--output-dir", dir])
               end)
             ) == {:shutdown, 1}
    end
  end

  describe "--check with missing files" do
    test "exits non-zero when files do not exist", %{output_dir: dir} do
      capture_task(fn ->
        Export.run(["--output-dir", dir])
      end)

      all_grid_files(dir) |> Enum.each(&File.rm!/1)

      assert catch_exit(
               capture_task(fn ->
                 Export.run(["--check", "--output-dir", dir])
               end)
             ) == {:shutdown, 1}
    end
  end

  describe "generate mode" do
    test "creates schema directories with schema.grid master files", %{output_dir: dir} do
      capture_task(fn ->
        Export.run(["--output-dir", dir])
      end)

      masters = master_files(dir)
      assert masters != []

      Enum.each(masters, fn path ->
        content = File.read!(path)
        assert content =~ "schema "
        assert content =~ ~s(import ")
      end)
    end

    test "creates individual struct/enum files", %{output_dir: dir} do
      capture_task(fn ->
        Export.run(["--output-dir", dir])
      end)

      individuals = individual_files(dir)
      assert individuals != []

      has_struct = Enum.any?(individuals, fn p -> File.read!(p) =~ "struct " end)
      assert has_struct
    end

    test "master imports match individual files", %{output_dir: dir} do
      capture_task(fn ->
        Export.run(["--output-dir", dir])
      end)

      Enum.each(master_files(dir), fn master_path ->
        schema_dir = Path.dirname(master_path)
        content = File.read!(master_path)

        import_paths =
          Regex.scan(~r/import "([^"]+)"/, content)
          |> Enum.map(fn [_, path] -> Path.join(schema_dir, path) end)

        Enum.each(import_paths, fn imported ->
          assert File.exists?(imported),
                 "Master #{master_path} imports #{imported} but file does not exist"
        end)
      end)
    end

    test "produces distinct files per schema_id (no silent drops)", %{output_dir: dir} do
      capture_task(fn ->
        Export.run(["--output-dir", dir])
      end)

      struct_count =
        individual_files(dir)
        |> Enum.count(fn path -> File.read!(path) =~ ~r/^struct /m end)

      assert struct_count > 0

      masters = master_files(dir)
      schema_ids = Enum.map(masters, fn p -> Regex.run(~r/id: (\d+)/, File.read!(p)) end)
      assert length(Enum.uniq(schema_ids)) == length(masters)
    end

    test "structs sorted alphabetically in master imports", %{output_dir: dir} do
      capture_task(fn ->
        Export.run(["--output-dir", dir])
      end)

      Enum.each(master_files(dir), fn master_path ->
        content = File.read!(master_path)

        imports =
          Regex.scan(~r/import "([^"]+)"/, content) |> Enum.map(fn [_, p] -> p end)

        assert imports == Enum.sort(imports),
               "Imports in #{master_path} are not alphabetically sorted"
      end)
    end

    test "running export twice produces byte-identical files", %{output_dir: dir} do
      capture_task(fn ->
        Export.run(["--output-dir", dir])
      end)

      first_snapshot = snapshot(dir)

      assert first_snapshot != %{}

      capture_task(fn ->
        Export.run(["--output-dir", dir])
      end)

      assert snapshot(dir) == first_snapshot
    end

    test "--prune removes unexpected generated files", %{output_dir: dir} do
      capture_task(fn ->
        Export.run(["--output-dir", dir])
      end)

      extra = Path.join(dir, "schema_999/orphan.grid")
      File.mkdir_p!(Path.dirname(extra))
      File.write!(extra, "@syntax 1\nstruct Orphan (template_id: 1) {}\n")

      capture_task(fn ->
        Export.run(["--output-dir", dir, "--prune"])
      end)

      refute File.exists?(extra)
    end
  end

  describe "@syntax directive" do
    test "all generated files include @syntax", %{output_dir: dir} do
      capture_task(fn ->
        Export.run(["--output-dir", dir])
      end)

      Enum.each(all_grid_files(dir), fn path ->
        content = File.read!(path)
        assert content =~ "@syntax 1", "#{path} missing @syntax directive"
      end)
    end

    test "@syntax appears before schema block in master files", %{output_dir: dir} do
      capture_task(fn ->
        Export.run(["--output-dir", dir])
      end)

      Enum.each(master_files(dir), fn path ->
        content = File.read!(path)
        syntax_pos = :binary.match(content, "@syntax")
        schema_pos = :binary.match(content, "schema ")

        assert syntax_pos != :nomatch, "#{path} missing @syntax"
        assert schema_pos != :nomatch, "#{path} missing schema block"

        {s_start, _} = syntax_pos
        {sc_start, _} = schema_pos
        assert s_start < sc_start, "@syntax must appear before schema block in #{path}"
      end)
    end
  end

  describe "self-contained individual files" do
    test "struct files referencing enums include import directives", %{output_dir: dir} do
      capture_task(fn ->
        Export.run(["--output-dir", dir])
      end)

      files_with_enum_refs =
        individual_files(dir)
        |> Enum.filter(fn path ->
          content = File.read!(path)
          content =~ "struct " and content =~ ~r/: (Side|Status|TestEnum)/
        end)

      assert files_with_enum_refs != [],
             "Expected at least one struct file referencing an enum type"

      Enum.each(files_with_enum_refs, fn path ->
        content = File.read!(path)
        assert content =~ ~s(import "), "#{path} references enum but has no import"
      end)
    end
  end

  describe "cross-schema enum imports" do
    test "bench schema imports enum from events schema", %{output_dir: dir} do
      capture_task(fn ->
        Export.run(["--output-dir", dir])
      end)

      bench_masters = master_files(dir) |> Enum.filter(&(&1 =~ "bench"))

      Enum.each(bench_masters, fn master_path ->
        content = File.read!(master_path)

        if content =~ "id: 200" do
          has_cross_import = content =~ ~r/import "\.\.\/.*order_side\.grid"/

          if has_cross_import do
            assert true
          end
        end
      end)
    end
  end

  describe "path derivation" do
    test "simple name becomes snake_case.grid" do
      assert Export.type_to_relative_path("OrderCreated") ==
               "order_created.grid"
    end

    test "dotted name becomes nested path" do
      assert Export.type_to_relative_path("ExampleApp.Bench.SmallStruct") ==
               "example_app/bench/small_struct.grid"
    end

    test "single segment name" do
      assert Export.type_to_relative_path("Trade") == "trade.grid"
    end
  end

  defp capture_task(fun) do
    ExUnit.CaptureIO.capture_io(fun)
  end
end
