defmodule Mix.Tasks.GridCodec.TestAudit do
  @shortdoc "Audit public GridCodec modules for test references"
  @moduledoc """
  Audits public `GridCodec.*` modules and fails when a module has no obvious
  test coverage reference in `test/**/*_test.exs`.

  This is a lightweight regression gate meant to catch new public modules that
  ship without any dedicated tests at all. It is heuristic-based rather than a
  substitute for line coverage:

  - a module counts as covered when a test file references either its full
    module name or its last segment (for aliased test files)
  - ignore lists can be configured via `mix.exs` under `:test_audit`

  ## Example

      mix grid_codec.test_audit
  """

  use Mix.Task

  @impl Mix.Task
  def run(_args) do
    modules = collect_modules()
    test_contents = collect_test_contents()
    ignored = ignored_modules()

    case audit(modules, test_contents, ignored) do
      [] ->
        Mix.shell().info("All public GridCodec modules have matching test references.")

      missing ->
        Mix.shell().error("Public modules without matching test references:\n")

        Enum.each(missing, fn {module_name, file_path} ->
          Mix.shell().error("  #{module_name} (#{file_path})")
        end)

        Mix.shell().error(
          "\nAdd or update tests so the module is referenced by at least one *_test.exs file."
        )

        exit({:shutdown, 1})
    end
  end

  @doc false
  def audit(modules, test_contents, ignored_modules) do
    ignored =
      ignored_modules
      |> Enum.map(&normalize_module_name/1)
      |> MapSet.new()

    Enum.reject(modules, fn {module_name, _file_path} ->
      MapSet.member?(ignored, module_name) or referenced_in_tests?(module_name, test_contents)
    end)
  end

  defp collect_modules do
    "lib/grid_codec/**/*.ex"
    |> Path.wildcard()
    |> Enum.flat_map(fn file_path ->
      file_path
      |> File.read!()
      |> module_entries(file_path)
    end)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp module_entries(contents, file_path) do
    Regex.scan(~r/defmodule\s+(GridCodec\.[A-Za-z0-9_.]+)/, contents, capture: :all_but_first)
    |> Enum.map(fn [module_name] -> {module_name, file_path} end)
  end

  defp collect_test_contents do
    "test/**/*_test.exs"
    |> Path.wildcard()
    |> Enum.map(&File.read!/1)
  end

  defp ignored_modules do
    Mix.Project.config()
    |> Keyword.get(:test_audit, [])
    |> Keyword.get(:ignore_modules, [])
  end

  defp referenced_in_tests?(module_name, test_contents) do
    last_segment =
      module_name
      |> String.split(".")
      |> List.last()

    Enum.any?(test_contents, fn test_content ->
      String.contains?(test_content, module_name) or String.contains?(test_content, last_segment)
    end)
  end

  defp normalize_module_name(module) when is_atom(module) do
    module
    |> Module.split()
    |> Enum.join(".")
  end

  defp normalize_module_name(module) when is_binary(module), do: module
end
