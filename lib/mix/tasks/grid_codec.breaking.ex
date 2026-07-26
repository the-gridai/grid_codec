defmodule Mix.Tasks.GridCodec.Breaking do
  @shortdoc "Detect breaking changes in .grid schema files"
  @moduledoc """
  Detects breaking changes in `.grid` schema files by comparing the current
  version against a baseline (git ref or file path).

  ## Usage

      # Use .grid_codec.exs defaults
      mix grid_codec.breaking

      # Override baseline
      mix grid_codec.breaking --against origin/main

      # Specific files
      mix grid_codec.breaking priv/schemas/trading.grid --against v1.2.0

      # Specific schema IDs (repeat the option as needed)
      mix grid_codec.breaking --schema-id 1 --schema-id 2 --against origin/main

      # Wire-only checks
      mix grid_codec.breaking --category wire

      # Custom config file
      mix grid_codec.breaking --config path/to/.grid_codec.exs

  ## Configuration

  Create a `.grid_codec.exs` file in your project root:

      [
        breaking: [
          schema_files: ["priv/schemas/**/*.grid"],
          schema_ids: [1, 2],
          against: "origin/main",
          category: :source,
          except: [:SOURCE_FIELD_RENAMED],
          include_docs: true,
          fail_on: [:error],
          severity_overrides: [DOC_FIELD_DOC_REMOVED: :error]
        ]
      ]

  CLI flags override config file values.

  ## Exit Codes

  - `0` - No breaking changes found
  - `1` - Breaking changes detected
  - `2` - Error (parse failure, git error, etc.)

  ## Categories

  - `:wire` - Binary wire format compatibility only
  - `:source` - Wire + Elixir API compatibility (default)

  See `docs/schema-evolution.md` for the recommended evolution workflow and the
  full rule reference for both categories.
  """

  use Mix.Task

  alias GridCodec.Breaking.Checker
  alias GridCodec.Breaking.Config
  alias GridCodec.Breaking.Policy
  alias GridCodec.Schema.Parser

  @switches [
    against: :string,
    category: :string,
    config: :string,
    schema_id: :keep
  ]

  @impl Mix.Task
  def run(args) do
    {opts, file_args, _} = OptionParser.parse(args, switches: @switches)

    with {:ok, schema_ids} <- parse_schema_ids(Keyword.get_values(opts, :schema_id)),
         cli_opts <-
           opts
           |> Keyword.delete(:schema_id)
           |> Keyword.put_new(:schema_ids, if(schema_ids != [], do: schema_ids, else: nil))
           |> Keyword.put_new(:schema_files, if(file_args != [], do: file_args, else: nil))
           |> Enum.reject(fn {_k, v} -> v == nil end),
         {:ok, config} <- Config.load(cli_opts) do
      run_checks(config)
    else
      {:error, reason} ->
        Mix.shell().error("Configuration error: #{inspect(reason)}")
        exit({:shutdown, 2})
    end
  end

  defp run_checks(config) do
    with files when files != [] <- resolve_files(config.schema_files),
         {:ok, selected_files} <- select_schema_files(files, config.schema_ids) do
      do_check_files(selected_files, config)
    else
      [] ->
        Mix.shell().info("No .grid files found matching #{inspect(config.schema_files)}")
        :ok

      {:error, reason} ->
        Mix.shell().error("Schema selection error: #{inspect(reason)}")
        exit({:shutdown, 2})
    end
  end

  defp do_check_files(files, config) do
    check_opts = %{
      category: config.category,
      except: config.except,
      include_docs: config.include_docs,
      severity_overrides: config.severity_overrides
    }

    {total_issues, file_count, error_count} =
      Enum.reduce(files, {[], 0, 0}, fn file_path, {all_issues, files_with_issues, errors} ->
        case check_file(file_path, config.against, check_opts) do
          {:ok, []} ->
            {all_issues, files_with_issues, errors}

          {:ok, issues} ->
            print_file_issues(file_path, issues)
            {all_issues ++ issues, files_with_issues + 1, errors}

          :new_file ->
            Mix.shell().info(
              "Skipping #{file_path}: schema is new relative to #{config.against}; export validation covers it."
            )

            {all_issues, files_with_issues, errors}

          {:error, reason} ->
            Mix.shell().error("Error checking #{file_path}: #{inspect(reason)}")
            {all_issues, files_with_issues, errors + 1}
        end
      end)

    count = length(total_issues)
    blocking_count = Enum.count(total_issues, &Policy.blocking?(&1, config.fail_on))

    cond do
      error_count > 0 ->
        Mix.shell().error("\nEncountered #{error_count} error(s) while checking schemas.")
        exit({:shutdown, 2})

      blocking_count > 0 ->
        Mix.shell().error(
          "\nFound #{count} issue(s) in #{file_count} file(s); #{blocking_count} are blocking under the current policy."
        )

        exit({:shutdown, 1})

      count > 0 ->
        Mix.shell().info(
          "\nFound #{count} non-blocking issue(s) in #{file_count} file(s) under the current policy."
        )

      true ->
        Mix.shell().info("No breaking changes detected.")
    end
  end

  defp check_file(file_path, against, check_opts) do
    with {:ok, new_content} <- File.read(file_path),
         true <- master_file?(new_content),
         {:ok, old_content} <- resolve_baseline(file_path, against) do
      opts_with_resolvers =
        check_opts
        |> Map.put(:new_resolver, &File.read/1)
        |> Map.put(:old_resolver, git_import_resolver(against))

      Checker.check_contents(old_content, new_content, file_path, opts_with_resolvers)
    else
      false -> {:ok, []}
      error -> error
    end
  end

  defp master_file?(content) do
    Regex.match?(~r/^\s*schema(?:\s+\w+)?\s*\{/m, content)
  end

  defp git_import_resolver(against) do
    fn full_path ->
      case Checker.baseline_from_git(against, full_path) do
        {:ok, content} -> {:ok, content}
        :new_file -> {:error, :enoent}
        error -> error
      end
    end
  end

  defp resolve_baseline(file_path, against) do
    if File.exists?(against) and not git_ref?(against) do
      case File.read(against) do
        {:ok, content} -> {:ok, content}
        {:error, reason} -> {:error, {:baseline_read_error, against, reason}}
      end
    else
      Checker.baseline_from_git(against, file_path)
    end
  end

  defp git_ref?(str) do
    not String.contains?(str, "/") or
      String.starts_with?(str, "origin/") or
      String.starts_with?(str, "refs/") or
      not String.ends_with?(str, ".grid")
  end

  defp parse_schema_ids(values) do
    values
    |> Enum.flat_map(&String.split(&1, ",", trim: true))
    |> Enum.reduce_while({:ok, []}, fn value, {:ok, ids} ->
      case Integer.parse(value) do
        {id, ""} when id in 0..65_535 -> {:cont, {:ok, [id | ids]}}
        _ -> {:halt, {:error, {:invalid_schema_id, value}}}
      end
    end)
    |> then(fn
      {:ok, ids} -> {:ok, ids |> Enum.uniq() |> Enum.sort()}
      error -> error
    end)
  end

  defp select_schema_files(files, []), do: {:ok, files}

  defp select_schema_files(files, schema_ids) do
    with {:ok, files_by_id} <- index_master_files(files),
         [] <- schema_ids -- Map.keys(files_by_id) do
      {:ok, Enum.map(schema_ids, &Map.fetch!(files_by_id, &1))}
    else
      {:error, _reason} = error -> error
      missing_ids -> {:error, {:schema_ids_not_found, missing_ids}}
    end
  end

  defp index_master_files(files) do
    Enum.reduce_while(files, {:ok, %{}}, fn file_path, {:ok, files_by_id} ->
      case master_schema_id(file_path) do
        {:ok, schema_id} ->
          case Map.fetch(files_by_id, schema_id) do
            {:ok, existing_path} ->
              {:halt, {:error, {:duplicate_schema_id, schema_id, existing_path, file_path}}}

            :error ->
              {:cont, {:ok, Map.put(files_by_id, schema_id, file_path)}}
          end

        :not_master ->
          {:cont, {:ok, files_by_id}}

        {:error, reason} ->
          {:halt, {:error, {:schema_parse_error, file_path, reason}}}
      end
    end)
  end

  defp master_schema_id(file_path) do
    with {:ok, content} <- File.read(file_path),
         true <- master_file?(content),
         {:ok, schema} <- Parser.parse(content),
         id when is_integer(id) <- schema.id do
      {:ok, id}
    else
      false -> :not_master
      {:error, reason} -> {:error, reason}
      nil -> {:error, :missing_schema_id}
    end
  end

  defp resolve_files(patterns) when is_list(patterns) do
    patterns
    |> Enum.flat_map(&Path.wildcard/1)
    |> Enum.filter(&String.ends_with?(&1, ".grid"))
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp print_file_issues(file_path, issues) do
    Mix.shell().info("\n#{file_path}:\n")

    Enum.each(issues, fn issue ->
      line = GridCodec.Breaking.Issue.format(issue)

      if issue.severity == :error do
        Mix.shell().error(line)
      else
        Mix.shell().info(line)
      end
    end)
  end
end
