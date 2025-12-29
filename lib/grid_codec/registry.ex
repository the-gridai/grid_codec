defmodule GridCodec.Registry do
  @moduledoc """
  Registry for discovering GridCodec modules in a system.

  ## Why a Registry?

  In large systems with many codecs, it's useful to:
  - List all available codecs at runtime
  - Validate codec configurations
  - Generate documentation automatically
  - Build codec catalogs for API documentation
  - Debug serialization issues

  ## Usage

  ### Finding All Codecs

      # List all codec modules
      GridCodec.Registry.list_codecs()
      #=> [MyApp.OrderEvent, MyApp.TradeEvent, ...]

      # Get codec info
      GridCodec.Registry.codec_info(MyApp.OrderEvent)
      #=> %{
      #=>   module: MyApp.OrderEvent,
      #=>   fields: [:id, :price, :quantity],
      #=>   block_length: 20,
      #=>   version: 1
      #=> }

  ### Finding Codecs by Criteria

      # Find codecs with a specific field
      GridCodec.Registry.find_by_field(:order_id)
      #=> [MyApp.OrderEvent, MyApp.CancelEvent]

      # Get all field names across all codecs
      GridCodec.Registry.all_fields()
      #=> [:order_id, :price, :quantity, :side, ...]

  ## Implementation

  This uses two approaches:
  1. **Compile-time registration**: Codecs register via `@after_compile`
  2. **Runtime discovery**: Scans loaded modules for codec behaviour

  Runtime discovery is more reliable as it doesn't require persistent storage.
  """

  @doc """
  Lists all GridCodec modules currently loaded in the system.

  This scans all loaded modules and checks if they implement GridCodec
  by looking for the `__schema__/0` and `encode/1` functions.

  ## Example

      iex> GridCodec.Registry.list_codecs()
      [MyApp.OrderEvent, MyApp.TradeEvent]

  ## Options

  - `:filter` - A function to filter codecs, receives module name
  - `:namespace` - Only return codecs under this namespace (e.g., `MyApp.Events`)
  """
  @spec list_codecs(keyword()) :: [module()]
  def list_codecs(opts \\ []) do
    filter_fn = Keyword.get(opts, :filter, fn _ -> true end)
    namespace = Keyword.get(opts, :namespace)

    :code.all_loaded()
    |> Enum.map(fn {mod, _} -> mod end)
    |> Enum.filter(&is_gridcodec?/1)
    |> Enum.filter(fn mod ->
      passes_namespace?(mod, namespace) and filter_fn.(mod)
    end)
    |> Enum.sort()
  end

  @doc """
  Returns detailed information about a codec module.

  ## Example

      iex> GridCodec.Registry.codec_info(MyApp.OrderEvent)
      %{
        module: MyApp.OrderEvent,
        fields: [:id, :price, :quantity],
        fixed_fields: [:id, :price, :quantity],
        var_fields: [],
        block_length: 20,
        version: 1,
        endian: :little
      }

  Returns `nil` if the module is not a valid GridCodec.
  """
  @spec codec_info(module()) :: map() | nil
  def codec_info(module) when is_atom(module) do
    if is_gridcodec?(module) do
      schema = module.__schema__()

      %{
        module: module,
        fields: module.__fields__(),
        fixed_fields: schema.fixed_fields,
        var_fields: schema.var_fields,
        groups: length(schema.groups),
        block_length: schema.block_length,
        version: schema.version,
        endian: schema.endian
      }
    else
      nil
    end
  end

  @doc """
  Finds all codecs that have a specific field.

  ## Example

      iex> GridCodec.Registry.find_by_field(:order_id)
      [MyApp.OrderEvent, MyApp.CancelEvent]
  """
  @spec find_by_field(atom(), keyword()) :: [module()]
  def find_by_field(field_name, opts \\ []) when is_atom(field_name) do
    list_codecs(opts)
    |> Enum.filter(fn mod ->
      field_name in mod.__fields__()
    end)
  end

  @doc """
  Returns all unique field names across all codecs.

  ## Example

      iex> GridCodec.Registry.all_fields()
      [:id, :order_id, :price, :quantity, :side, :timestamp]
  """
  @spec all_fields(keyword()) :: [atom()]
  def all_fields(opts \\ []) do
    list_codecs(opts)
    |> Enum.flat_map(fn mod -> mod.__fields__() end)
    |> Enum.uniq()
    |> Enum.sort()
  end

  @doc """
  Generates a summary report of all codecs in the system.

  ## Example

      iex> GridCodec.Registry.summary()
      %{
        total_codecs: 5,
        total_fields: 23,
        total_block_bytes: 156,
        codecs: [
          %{module: MyApp.OrderEvent, fields: 7, block_length: 46},
          ...
        ]
      }
  """
  @spec summary(keyword()) :: map()
  def summary(opts \\ []) do
    codecs = list_codecs(opts)

    codec_summaries =
      Enum.map(codecs, fn mod ->
        info = codec_info(mod)

        %{
          module: mod,
          fields: length(info.fields),
          block_length: info.block_length,
          has_groups: info.groups > 0,
          has_var_fields: length(info.var_fields) > 0
        }
      end)

    %{
      total_codecs: length(codecs),
      total_fields: codec_summaries |> Enum.map(& &1.fields) |> Enum.sum(),
      total_block_bytes: codec_summaries |> Enum.map(& &1.block_length) |> Enum.sum(),
      codecs: codec_summaries
    }
  end

  @doc """
  Validates that a module is a valid GridCodec.

  Returns `{:ok, info}` or `{:error, reason}`.

  ## Example

      iex> GridCodec.Registry.validate(MyApp.OrderEvent)
      {:ok, %{module: MyApp.OrderEvent, fields: [:id, :price], ...}}

      iex> GridCodec.Registry.validate(String)
      {:error, :not_a_gridcodec}
  """
  @spec validate(module()) :: {:ok, map()} | {:error, atom()}
  def validate(module) when is_atom(module) do
    cond do
      not Code.ensure_loaded?(module) ->
        {:error, :module_not_found}

      not is_gridcodec?(module) ->
        {:error, :not_a_gridcodec}

      true ->
        {:ok, codec_info(module)}
    end
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  defp is_gridcodec?(module) do
    Code.ensure_loaded?(module) and
      function_exported?(module, :__schema__, 0) and
      function_exported?(module, :__fields__, 0) and
      function_exported?(module, :encode, 1) and
      function_exported?(module, :decode, 1)
  end

  defp passes_namespace?(_mod, nil), do: true

  defp passes_namespace?(mod, namespace) when is_atom(namespace) do
    mod_string = Atom.to_string(mod)
    namespace_string = Atom.to_string(namespace)
    String.starts_with?(mod_string, namespace_string)
  end
end
