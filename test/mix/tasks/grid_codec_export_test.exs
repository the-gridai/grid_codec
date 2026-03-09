defmodule Mix.Tasks.GridCodec.ExportTest do
  use ExUnit.Case, async: true

  @tmp_base Path.join(System.tmp_dir!(), "grid_codec_export_check_test")

  setup do
    dir = Path.join(@tmp_base, "#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)

    %{output_dir: dir}
  end

  describe "--check with up-to-date files" do
    test "exits 0 when files match generated output", %{output_dir: dir} do
      capture_task(fn ->
        Mix.Tasks.GridCodec.Export.run(["--output-dir", dir])
      end)

      grid_files = Path.wildcard(Path.join(dir, "*.grid"))
      assert grid_files != []

      assert capture_task(fn ->
               Mix.Tasks.GridCodec.Export.run(["--check", "--output-dir", dir])
             end) =~ "up to date"
    end
  end

  describe "--check with stale files" do
    test "exits non-zero when a file differs", %{output_dir: dir} do
      capture_task(fn ->
        Mix.Tasks.GridCodec.Export.run(["--output-dir", dir])
      end)

      [first | _] = Path.wildcard(Path.join(dir, "*.grid"))
      File.write!(first, File.read!(first) <> "\n# stale")

      assert catch_exit(
               capture_task(fn ->
                 Mix.Tasks.GridCodec.Export.run(["--check", "--output-dir", dir])
               end)
             ) == {:shutdown, 1}
    end
  end

  describe "--check with missing files" do
    test "exits non-zero when files do not exist", %{output_dir: dir} do
      capture_task(fn ->
        Mix.Tasks.GridCodec.Export.run(["--output-dir", dir])
      end)

      Path.wildcard(Path.join(dir, "*.grid")) |> Enum.each(&File.rm!/1)

      assert catch_exit(
               capture_task(fn ->
                 Mix.Tasks.GridCodec.Export.run(["--check", "--output-dir", dir])
               end)
             ) == {:shutdown, 1}
    end
  end

  describe "generate mode (no --check)" do
    test "writes .grid files to output dir", %{output_dir: dir} do
      capture_task(fn ->
        Mix.Tasks.GridCodec.Export.run(["--output-dir", dir])
      end)

      grid_files = Path.wildcard(Path.join(dir, "*.grid"))
      assert grid_files != []

      Enum.each(grid_files, fn path ->
        content = File.read!(path)
        assert content =~ "schema "
        assert content =~ "struct "
      end)
    end
  end

  defp capture_task(fun) do
    ExUnit.CaptureIO.capture_io(fun)
  end
end
