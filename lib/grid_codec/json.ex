defmodule GridCodec.Json do
  @moduledoc """
  Simple JSON transcoder for GridCodec structs.

  Converts between GridCodec binary format and JSON using the naive approach:
  - Encode: `GridCodec.decode → Map.from_struct → Jason.encode`
  - Decode: `Jason.decode → struct → GridCodec.encode`

  ## Requirements

  For this to work, your struct fields must be JSON-serializable:
  - Use `:uuid_string` instead of `:uuid` for JSON-safe UUIDs
  - Integers, floats, booleans, strings work out of the box
  - For custom types, implement the `Jason.Encoder` protocol

  ## Examples

      # Encode GridCodec binary to JSON
      {:ok, json} = GridCodec.Json.encode(binary, MyApp.Order)

      # Decode JSON to GridCodec binary
      {:ok, binary} = GridCodec.Json.decode(json, MyApp.Order)

  ## Options

  Encoding options (passed to `Jason.encode/2`):
  - `:pretty` - Pretty print the JSON (default: false)

  Decoding options:
  - `:keys` - How to handle JSON keys, `:atoms` or `:strings` (default: `:strings`)
  """

  @doc """
  Encodes a GridCodec binary to JSON.

  ## Examples

      {:ok, json} = GridCodec.Json.encode(binary, MyApp.Order)
      {:ok, json} = GridCodec.Json.encode(binary, MyApp.Order, pretty: true)
  """
  @spec encode(binary(), module(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def encode(binary, schema, opts \\ []) when is_binary(binary) and is_atom(schema) do
    with {:ok, struct} <- schema.decode(binary) do
      jason_opts = if opts[:pretty], do: [pretty: true], else: []

      case Jason.encode(Map.from_struct(struct), jason_opts) do
        {:ok, json} -> {:ok, json}
        {:error, reason} -> {:error, {:json_encode_error, reason}}
      end
    end
  end

  @doc """
  Encodes a GridCodec binary to JSON, raising on error.

  ## Examples

      json = GridCodec.Json.encode!(binary, MyApp.Order)
      json = GridCodec.Json.encode!(binary, MyApp.Order, pretty: true)
  """
  @spec encode!(binary(), module(), keyword()) :: String.t()
  def encode!(binary, schema, opts \\ []) do
    case encode(binary, schema, opts) do
      {:ok, json} -> json
      {:error, reason} -> raise "Failed to encode to JSON: #{inspect(reason)}"
    end
  end

  @doc """
  Decodes JSON to a GridCodec binary.

  ## Examples

      {:ok, binary} = GridCodec.Json.decode(json, MyApp.Order)
  """
  @spec decode(String.t(), module(), keyword()) :: {:ok, binary()} | {:error, term()}
  def decode(json, schema, opts \\ []) when is_binary(json) and is_atom(schema) do
    keys = Keyword.get(opts, :keys, :strings)

    with {:ok, map} <- Jason.decode(json, keys: keys),
         {:ok, struct} <- build_struct(map, schema) do
      {:ok, schema.encode(struct)}
    else
      {:error, %Jason.DecodeError{} = e} -> {:error, {:json_decode_error, e}}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Decodes JSON to a GridCodec binary, raising on error.

  ## Examples

      binary = GridCodec.Json.decode!(json, MyApp.Order)
  """
  @spec decode!(String.t(), module(), keyword()) :: binary()
  def decode!(json, schema, opts \\ []) do
    case decode(json, schema, opts) do
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
end
