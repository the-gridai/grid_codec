defmodule GridCodec.Breaking.Config do
  @moduledoc """
  Loads and merges configuration from `.grid_codec.exs` and CLI options.

  Configuration is resolved in order of precedence (highest first):
  1. CLI flags passed to the mix task
  2. `.grid_codec.exs` file in the project root
  3. Built-in defaults
  """

  @default_config %{
    schema_files: ["priv/schemas/**/*.grid"],
    against: "origin/main",
    category: :source,
    except: []
  }

  @type t :: %{
          schema_files: [String.t()],
          against: String.t(),
          category: :wire | :source,
          except: [atom()]
        }

  @doc """
  Loads config by merging defaults, `.grid_codec.exs`, and CLI overrides.
  """
  @spec load(keyword()) :: {:ok, t()} | {:error, term()}
  def load(cli_opts \\ []) do
    with {:ok, file_config} <- load_config_file(cli_opts[:config]) do
      merged =
        @default_config
        |> merge_file_config(file_config)
        |> merge_cli_opts(cli_opts)

      {:ok, merged}
    end
  end

  @doc "Returns the default configuration."
  @spec defaults() :: t()
  def defaults, do: @default_config

  defp load_config_file(nil) do
    path = Path.join(File.cwd!(), ".grid_codec.exs")

    if File.exists?(path) do
      eval_config_file(path)
    else
      {:ok, []}
    end
  end

  defp load_config_file(path) do
    if File.exists?(path) do
      eval_config_file(path)
    else
      {:error, {:config_not_found, path}}
    end
  end

  defp eval_config_file(path) do
    {config, _bindings} = Code.eval_file(path)

    if is_list(config) do
      {:ok, config}
    else
      {:error, {:invalid_config, path, "expected a keyword list"}}
    end
  rescue
    e -> {:error, {:config_eval_error, path, Exception.message(e)}}
  end

  defp merge_file_config(defaults, file_config) do
    breaking = Keyword.get(file_config, :breaking, [])

    Enum.reduce(breaking, defaults, fn
      {:schema_files, v}, acc when is_list(v) -> %{acc | schema_files: v}
      {:against, v}, acc when is_binary(v) -> %{acc | against: v}
      {:category, v}, acc when v in [:wire, :source] -> %{acc | category: v}
      {:except, v}, acc when is_list(v) -> %{acc | except: v}
      _, acc -> acc
    end)
  end

  defp merge_cli_opts(config, cli_opts) do
    config
    |> maybe_put(:against, cli_opts[:against])
    |> maybe_put(:category, parse_category(cli_opts[:category]))
    |> maybe_put(:schema_files, cli_opts[:schema_files])
  end

  defp maybe_put(config, _key, nil), do: config
  defp maybe_put(config, key, value), do: Map.put(config, key, value)

  defp parse_category(nil), do: nil
  defp parse_category("wire"), do: :wire
  defp parse_category("source"), do: :source
  defp parse_category(:wire), do: :wire
  defp parse_category(:source), do: :source
  defp parse_category(_), do: nil
end
