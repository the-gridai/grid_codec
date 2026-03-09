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

      # Wire-only checks
      mix grid_codec.breaking --category wire

      # Custom config file
      mix grid_codec.breaking --config path/to/.grid_codec.exs

  ## Configuration

  Create a `.grid_codec.exs` file in your project root:

      [
        breaking: [
          schema_files: ["priv/schemas/**/*.grid"],
          against: "origin/main",
          category: :source,
          except: [:SOURCE_FIELD_RENAMED]
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
  """

  use Mix.Task

  alias GridCodec.Breaking.{Checker, Config}

  @switches [
    against: :string,
    category: :string,
    config: :string
  ]

  @impl Mix.Task
  def run(args) do
    {opts, file_args, _} = OptionParser.parse(args, switches: @switches)

    cli_opts =
      opts
      |> Keyword.put_new(:schema_files, if(file_args != [], do: file_args, else: nil))
      |> Enum.reject(fn {_k, v} -> v == nil end)

    case Config.load(cli_opts) do
      {:ok, config} ->
        run_checks(config)

      {:error, reason} ->
        Mix.shell().error("Configuration error: #{inspect(reason)}")
        exit({:shutdown, 2})
    end
  end

  defp run_checks(config) do
    files = resolve_files(config.schema_files)

    if files == [] do
      Mix.shell().info("No .grid files found matching #{inspect(config.schema_files)}")
      :ok
    else
      do_check_files(files, config)
    end
  end

  defp do_check_files(files, config) do
    check_opts = %{
      category: config.category,
      except: config.except
    }

    {total_issues, file_count} =
      Enum.reduce(files, {[], 0}, fn file_path, {all_issues, files_with_issues} ->
        case check_file(file_path, config.against, check_opts) do
          {:ok, []} ->
            {all_issues, files_with_issues}

          {:ok, issues} ->
            print_file_issues(file_path, issues)
            {all_issues ++ issues, files_with_issues + 1}

          :new_file ->
            {all_issues, files_with_issues}

          {:error, reason} ->
            Mix.shell().error("Error checking #{file_path}: #{inspect(reason)}")
            {all_issues, files_with_issues}
        end
      end)

    count = length(total_issues)

    if count > 0 do
      Mix.shell().error("\nFound #{count} breaking change(s) in #{file_count} file(s).")
      exit({:shutdown, 1})
    else
      Mix.shell().info("No breaking changes detected.")
    end
  end

  defp check_file(file_path, against, check_opts) do
    with {:ok, new_content} <- File.read(file_path),
         {:ok, old_content} <- resolve_baseline(file_path, against) do
      Checker.check_contents(old_content, new_content, file_path, check_opts)
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

      if issue.category == :wire do
        Mix.shell().error(line)
      else
        Mix.shell().info(line)
      end
    end)
  end
end
