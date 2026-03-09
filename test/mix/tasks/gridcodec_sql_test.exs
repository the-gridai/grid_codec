defmodule Mix.Tasks.Gridcodec.SqlTest do
  # async: false because generate_all() scans :code.all_loaded() which changes
  # as other async test files define inline GridCodec modules
  use ExUnit.Case, async: false

  @tmp_base Path.join(System.tmp_dir!(), "gridcodec_sql_check_test")

  setup do
    dir = Path.join(@tmp_base, "#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)

    %{output_path: Path.join(dir, "gridcodec_functions.sql")}
  end

  describe "--check with up-to-date file" do
    test "exits 0 when file matches generated output", %{output_path: path} do
      {:ok, _} = GridCodec.SQL.generate_all_to_file(path)

      assert capture_task(fn ->
               Mix.Tasks.Gridcodec.Sql.run(["--check", "--output", path])
             end) =~ "up to date"
    end
  end

  describe "--check with stale file" do
    test "exits non-zero when file differs", %{output_path: path} do
      {:ok, _} = GridCodec.SQL.generate_all_to_file(path)
      File.write!(path, File.read!(path) <> "\n-- stale")

      assert catch_exit(
               capture_task(fn ->
                 Mix.Tasks.Gridcodec.Sql.run(["--check", "--output", path])
               end)
             ) == {:shutdown, 1}
    end
  end

  describe "--check with missing file" do
    test "exits non-zero when file does not exist", %{output_path: path} do
      refute File.exists?(path)

      assert catch_exit(
               capture_task(fn ->
                 Mix.Tasks.Gridcodec.Sql.run(["--check", "--output", path])
               end)
             ) == {:shutdown, 1}
    end
  end

  describe "generate mode (no --check)" do
    test "writes file to disk", %{output_path: path} do
      capture_task(fn ->
        Mix.Tasks.Gridcodec.Sql.run(["--output", path])
      end)

      assert File.exists?(path)
      assert File.read!(path) =~ "CREATE SCHEMA IF NOT EXISTS gridcodec;"
    end
  end

  defp capture_task(fun) do
    ExUnit.CaptureIO.capture_io(fun)
  end
end
