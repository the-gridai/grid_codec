defmodule GridCodec.BinaryInspector do
  @moduledoc """
  Inspects GridCodec binaries without requiring full application-level decode logic.

  This utility is aimed at debugging and operational tooling:
  - Decode header metadata
  - Resolve schema via registry (for framed binaries)
  - Show fixed-field layout with offsets, sizes, raw bytes, and extracted values
  - Summarize variable fields and groups from schema metadata
  """

  import Kernel, except: [inspect: 1, inspect: 2]

  @type inspect_result :: %{
          binary_size: non_neg_integer(),
          schema: module(),
          header: map() | nil,
          payload_size: non_neg_integer(),
          fixed_block_size: non_neg_integer(),
          fixed_fields: [map()],
          variable_fields: [atom()],
          groups: [atom()]
        }

  @doc """
  Inspects a GridCodec binary.

  ## Options

  - `:schema` - Explicit schema module. If omitted and header is enabled, schema is resolved via registry.
  - `:header` - Whether binary includes GridCodec header (default: `true`)
  """
  @spec inspect(binary(), keyword()) :: {:ok, inspect_result()} | {:error, term()}
  def inspect(binary, opts \\ []) when is_binary(binary) do
    schema_opt = Keyword.get(opts, :schema)
    has_header = Keyword.get(opts, :header, true)

    with {:ok, schema, header_info, payload} <-
           resolve_schema_and_payload(binary, schema_opt, has_header),
         {:ok, fixed_fields} <- inspect_fixed_fields(binary, payload, schema, has_header) do
      schema_info = schema.__schema__()

      {:ok,
       %{
         binary_size: byte_size(binary),
         schema: schema,
         header: header_info,
         payload_size: byte_size(payload),
         fixed_block_size: schema_info.block_length,
         fixed_fields: fixed_fields,
         variable_fields: schema_info.var_fields,
         groups: Enum.map(schema_info.groups, fn {name, _fields, _opts} -> name end)
       }}
    end
  end

  @doc """
  Inspects a binary and raises on error.
  """
  @spec inspect!(binary(), keyword()) :: inspect_result()
  def inspect!(binary, opts \\ []) do
    case inspect(binary, opts) do
      {:ok, result} ->
        result

      {:error, reason} ->
        raise ArgumentError, "failed to inspect GridCodec binary: #{Kernel.inspect(reason)}"
    end
  end

  defp resolve_schema_and_payload(binary, schema, true)
       when is_atom(schema) and not is_nil(schema) do
    case GridCodec.Header.decode(binary) do
      {:ok, header_info, payload} -> {:ok, schema, header_info, payload}
      {:error, reason} -> {:error, {:invalid_header, reason}}
    end
  end

  defp resolve_schema_and_payload(binary, nil, true) do
    with {:ok, header_info, payload} <- GridCodec.Header.decode(binary),
         {:ok, schema} <-
           GridCodec.Registry.lookup(header_info.schema_id, header_info.template_id) do
      {:ok, schema, header_info, payload}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp resolve_schema_and_payload(binary, schema, false)
       when is_atom(schema) and not is_nil(schema) do
    {:ok, schema, nil, binary}
  end

  defp resolve_schema_and_payload(_binary, nil, false) do
    {:error, :schema_required_without_header}
  end

  defp inspect_fixed_fields(binary, payload, schema, has_header) do
    field_types =
      schema.__schema__().fields
      |> Enum.into(%{}, fn {name, type, _opts} -> {name, type} end)

    specs = schema.__field_specs__(header: has_header)

    fixed_specs =
      specs
      |> Enum.filter(fn {_name, spec} ->
        match?({mod, _offset, _endian} when is_atom(mod), spec)
      end)
      |> Enum.map(fn {name, {type_module, offset, endian}} ->
        size = type_module.size()

        raw =
          if has_header do
            binary_part(binary, offset, size)
          else
            binary_part(payload, offset, size)
          end

        %{
          name: name,
          type: Map.get(field_types, name),
          type_module: type_module,
          offset: offset,
          size: size,
          raw_hex: Base.encode16(raw, case: :lower),
          value: type_module.get_value(if(has_header, do: binary, else: payload), offset, endian)
        }
      end)
      |> Enum.sort_by(& &1.offset)

    {:ok, fixed_specs}
  rescue
    e -> {:error, {:inspect_failed, e}}
  end
end
