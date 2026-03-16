defmodule GridCodec.Breaking.Checker do
  @moduledoc """
  Orchestrates breaking change detection between two parsed schemas.

  Runs the differ, applies WIRE and SOURCE rules based on the configured
  category, filters out excluded rules, and returns sorted issues.
  """

  alias GridCodec.Breaking.Differ
  alias GridCodec.Breaking.Issue
  alias GridCodec.Breaking.Rules.Source
  alias GridCodec.Breaking.Rules.Wire
  alias GridCodec.Schema.Parser
  alias GridCodec.Schema.Parser.Schema

  @type import_resolver :: (String.t() -> {:ok, String.t()} | {:error, term()})

  @type check_opts :: %{
          optional(:category) => :wire | :source,
          optional(:except) => [atom()],
          optional(:old_resolver) => import_resolver(),
          optional(:new_resolver) => import_resolver()
        }

  @doc """
  Compares two parsed schemas and returns breaking change issues.

  Options:
  - `:category` - `:wire` (wire-only) or `:source` (wire + source, default)
  - `:except` - list of rule atoms to exclude
  """
  @spec check(Schema.t(), Schema.t(), String.t(), check_opts()) :: [Issue.t()]
  def check(%Schema{} = old_schema, %Schema{} = new_schema, path, opts \\ %{}) do
    category = Map.get(opts, :category, :source)
    except = MapSet.new(Map.get(opts, :except, []))

    schema_diff = Differ.diff(old_schema, new_schema)

    issues = Wire.check(schema_diff, path)

    issues =
      if category == :source do
        issues ++ Source.check(schema_diff, path)
      else
        issues
      end

    issues
    |> Enum.reject(fn issue -> MapSet.member?(except, issue.rule) end)
    |> Enum.sort_by(fn issue -> {category_order(issue.category), issue.rule, issue.path} end)
  end

  @doc """
  High-level entrypoint: parses two `.grid` file contents and checks for breaking changes.

  Accepts an optional `import_resolver` function for resolving `import` directives.
  The resolver receives an import path and returns `{:ok, content}` or `{:error, reason}`.
  """
  @spec check_contents(String.t(), String.t(), String.t(), check_opts()) ::
          {:ok, [Issue.t()]} | {:error, term()}
  def check_contents(old_content, new_content, path, opts \\ %{}) do
    with {:ok, old_schema} <- parse_with_imports(old_content, path, opts[:old_resolver]),
         {:ok, new_schema} <- parse_with_imports(new_content, path, opts[:new_resolver]) do
      {:ok, check(old_schema, new_schema, path, opts)}
    end
  end

  defp parse_with_imports(content, _path, nil) do
    Parser.parse(content)
  end

  defp parse_with_imports(content, path, resolver) when is_function(resolver, 1) do
    with {:ok, schema} <- Parser.parse(content) do
      resolve_schema_imports(schema, Path.dirname(path), resolver, %{path => true})
    end
  end

  defp resolve_schema_imports(%Schema{imports: []} = schema, _base, _resolver, _visited) do
    {:ok, schema}
  end

  defp resolve_schema_imports(%Schema{imports: imports} = schema, base, resolver, visited) do
    Enum.reduce_while(imports, {:ok, schema}, fn import_path, {:ok, acc} ->
      full_path = Path.join(base, import_path)

      if Map.has_key?(visited, full_path) do
        {:halt, {:error, {:circular_import, full_path}}}
      else
        case resolver.(full_path) do
          {:ok, imported_content} ->
            visited = Map.put(visited, full_path, true)

            case Parser.parse(imported_content) do
              {:ok, imported} ->
                with {:ok, resolved} <-
                       resolve_schema_imports(
                         imported,
                         Path.dirname(full_path),
                         resolver,
                         visited
                       ) do
                  merged = %{
                    acc
                    | types: Map.merge(acc.types, resolved.types),
                      enums: Map.merge(acc.enums, resolved.enums),
                      structs: Map.merge(acc.structs, resolved.structs)
                  }

                  {:cont, {:ok, merged}}
                else
                  err -> {:halt, err}
                end

              err ->
                {:halt, err}
            end

          {:error, :enoent} ->
            {:cont, {:ok, acc}}

          {:error, _} = err ->
            {:halt, err}
        end
      end
    end)
  end

  @doc """
  Retrieves baseline file content from a git ref using `git show`.
  """
  @spec baseline_from_git(String.t(), String.t()) ::
          {:ok, String.t()} | :new_file | {:error, term()}
  def baseline_from_git(git_ref, file_path) do
    case System.cmd("git", ["show", "#{git_ref}:#{file_path}"], stderr_to_stdout: true) do
      {content, 0} ->
        {:ok, content}

      {error_output, _code} ->
        cond do
          String.contains?(error_output, "does not exist") ->
            :new_file

          String.contains?(error_output, "not a valid object") ->
            {:error, {:invalid_git_ref, git_ref}}

          true ->
            {:error, {:git_error, error_output}}
        end
    end
  end

  defp category_order(:wire), do: 0
  defp category_order(:source), do: 1
end
