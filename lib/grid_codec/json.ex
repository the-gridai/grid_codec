defmodule GridCodec.Json do
  @moduledoc """
  Simple JSON transcoder for GridCodec structs.

  Converts between GridCodec binary format and JSON using the naive approach:
  - Encode: `GridCodec.decode → Map.from_struct → JSON.encode!`
  - Decode: `JSON.decode → struct → GridCodec.encode`

  Uses Elixir's built-in `JSON` module (available since Elixir 1.18).

  ## Requirements

  For this to work, your struct fields must be JSON-serializable:
  - Use `:uuid_string` instead of `:uuid` for JSON-safe UUIDs
  - Integers, floats, booleans, strings work out of the box
  - For custom types, implement the `JSON.Encoder` protocol

  ## Examples

      # Encode GridCodec binary to JSON
      {:ok, json} = GridCodec.Json.encode(binary, MyApp.Order)

      # Decode JSON to GridCodec binary
      {:ok, binary} = GridCodec.Json.decode(json, MyApp.Order)

  ## Options

  Encoding options:
  - `:pretty` - Pretty print the JSON (default: false)

  Decoding options:
  - `:keys` - How to handle JSON keys, `:atoms` or `:strings` (default: `:strings`)
  """

  @doc """
  Converts a GridCodec binary to a plain map.

  Uses top-level dispatch when `schema` is not provided.
  """
  @spec to_map(binary(), keyword()) :: {:ok, map()} | {:error, term()}
  def to_map(binary, opts \\ []) when is_binary(binary) do
    case Keyword.get(opts, :schema) do
      nil ->
        with {:ok, struct} <- GridCodec.decode(binary) do
          {:ok, Map.from_struct(struct)}
        end

      schema when is_atom(schema) ->
        with {:ok, struct} <- schema.decode(binary) do
          {:ok, Map.from_struct(struct)}
        end
    end
  end

  @doc """
  Builds a GridCodec binary from a map and schema.

  ## Options

  - `:header` - Include GridCodec header on encode (default: `true`)
  """
  @spec from_map(map(), module(), keyword()) :: {:ok, binary()} | {:error, term()}
  def from_map(map, schema, opts \\ []) when is_map(map) and is_atom(schema) do
    with {:ok, struct} <- build_struct(map, schema),
         {:ok, binary} <- schema.encode(struct, header: Keyword.get(opts, :header, true)) do
      {:ok, binary}
    end
  end

  @doc """
  Encodes a GridCodec binary to JSON.

  Deprecated: use `to_json/3` instead.
  """
  @deprecated "Use to_json/3 instead"
  @spec encode(binary(), module(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def encode(binary, schema, opts \\ []) when is_binary(binary) and is_atom(schema) do
    to_json(binary, schema, opts)
  end

  @doc """
  Encodes a GridCodec binary to JSON with schema dispatch.

  ## Examples

      {:ok, json} = GridCodec.Json.to_json(binary)
      {:ok, json} = GridCodec.Json.to_json(binary, MyApp.Order, pretty: true)
  """
  @spec to_json(binary(), module() | keyword(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def to_json(binary, schema_or_opts \\ [], opts \\ [])

  def to_json(binary, opts, _opts2) when is_binary(binary) and is_list(opts) do
    with {:ok, map} <- to_map(binary, opts) do
      json_encode_map(map, opts)
    end
  end

  def to_json(binary, schema, opts) when is_binary(binary) and is_atom(schema) do
    with {:ok, map} <- to_map(binary, Keyword.put(opts, :schema, schema)) do
      json_encode_map(map, opts)
    end
  end

  @doc """
  Encodes a GridCodec binary to JSON, raising on error.

  Deprecated: use `to_json/3` with pattern matching instead.
  """
  @deprecated "Use to_json/3 with pattern matching instead"
  @spec encode!(binary(), module(), keyword()) :: String.t()
  def encode!(binary, schema, opts \\ []) do
    case to_json(binary, schema, opts) do
      {:ok, json} -> json
      {:error, reason} -> raise "Failed to encode to JSON: #{inspect(reason)}"
    end
  end

  @doc """
  Decodes JSON to a GridCodec binary.

  Deprecated: use `from_json/3` instead.
  """
  @deprecated "Use from_json/3 instead"
  @spec decode(String.t(), module(), keyword()) :: {:ok, binary()} | {:error, term()}
  def decode(json, schema, opts \\ []) when is_binary(json) and is_atom(schema) do
    from_json(json, schema, opts)
  end

  @doc """
  Decodes JSON into a GridCodec binary for the given schema.
  """
  @spec from_json(String.t(), module(), keyword()) :: {:ok, binary()} | {:error, term()}
  def from_json(json, schema, opts \\ []) when is_binary(json) and is_atom(schema) do
    keys = Keyword.get(opts, :keys, :strings)

    with {:ok, raw_map} <- JSON.decode(json),
         map = if(keys == :atoms, do: atomize_keys(raw_map), else: raw_map),
         {:ok, binary} <- from_map(map, schema, opts) do
      {:ok, binary}
    else
      {:error, reason} -> {:error, {:json_decode_error, reason}}
    end
  end

  @doc """
  Decodes JSON to a GridCodec binary, raising on error.

  Deprecated: use `from_json/3` with pattern matching instead.
  """
  @deprecated "Use from_json/3 with pattern matching instead"
  @spec decode!(String.t(), module(), keyword()) :: binary()
  def decode!(json, schema, opts \\ []) do
    case from_json(json, schema, opts) do
      {:ok, binary} -> binary
      {:error, reason} -> raise "Failed to decode from JSON: #{inspect(reason)}"
    end
  end

  # Build struct from map, handling both string and atom keys
  defp build_struct(map, schema) when is_map(map) do
    field_names = schema.__fields__()

    struct_map =
      Enum.reduce(field_names, %{}, fn field_name, acc ->
        value = Map.get(map, field_name) || Map.get(map, Atom.to_string(field_name))
        Map.put(acc, field_name, value)
      end)

    {:ok, struct(schema, struct_map)}
  rescue
    e -> {:error, {:struct_build_error, e}}
  end

  defp json_encode_map(map, opts) do
    if opts[:pretty] do
      {:ok, map |> do_pretty(0) |> IO.iodata_to_binary()}
    else
      {:ok, JSON.encode!(map)}
    end
  rescue
    e -> {:error, {:json_encode_error, e}}
  end

  defp atomize_keys(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {String.to_existing_atom(k), v} end)
  end

  defp do_pretty(map, indent) when is_map(map) do
    if map_size(map) == 0 do
      "{}"
    else
      pad = String.duplicate("  ", indent + 1)
      close_pad = String.duplicate("  ", indent)

      entries =
        Enum.map(Map.to_list(map), fn {k, v} ->
          [pad, JSON.encode!(k), ": ", do_pretty(v, indent + 1)]
        end)

      ["{\n", Enum.intersperse(entries, ",\n"), "\n", close_pad, "}"]
    end
  end

  defp do_pretty(list, indent) when is_list(list) do
    if list == [] do
      "[]"
    else
      pad = String.duplicate("  ", indent + 1)
      close_pad = String.duplicate("  ", indent)

      entries =
        Enum.map(list, fn v ->
          [pad, do_pretty(v, indent + 1)]
        end)

      ["[\n", Enum.intersperse(entries, ",\n"), "\n", close_pad, "]"]
    end
  end

  defp do_pretty(other, _indent), do: JSON.encode!(other)
end
