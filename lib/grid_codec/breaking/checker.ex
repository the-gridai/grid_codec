defmodule GridCodec.Breaking.Checker do
  @moduledoc """
  Orchestrates breaking change detection between two parsed schemas.

  Runs the differ, applies WIRE and SOURCE rules based on the configured
  category, filters out excluded rules, and returns sorted issues.
  """

  alias GridCodec.Breaking.{Differ, Issue}
  alias GridCodec.Breaking.Rules.{Wire, Source}
  alias GridCodec.Schema.Parser
  alias GridCodec.Schema.Parser.Schema

  @type check_opts :: %{
          optional(:category) => :wire | :source,
          optional(:except) => [atom()]
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
  """
  @spec check_contents(String.t(), String.t(), String.t(), check_opts()) ::
          {:ok, [Issue.t()]} | {:error, term()}
  def check_contents(old_content, new_content, path, opts \\ %{}) do
    with {:ok, old_schema} <- Parser.parse(old_content),
         {:ok, new_schema} <- Parser.parse(new_content) do
      {:ok, check(old_schema, new_schema, path, opts)}
    end
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
