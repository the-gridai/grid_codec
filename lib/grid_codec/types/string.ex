defmodule GridCodec.Types.String do
  @moduledoc """
  Variable-length UTF-8 string type with configurable length prefix.

  GridCodec supports three string variants with different length prefixes:

  | Type | Prefix | Max Length | Use Case |
  |------|--------|------------|----------|
  | `:string8` | u8 | 255 bytes | Short strings, names |
  | `:string16` | u16 | 65,535 bytes | Medium strings (default) |
  | `:string32` | u32 | 4GB | Large text, rare |

  The default `:string` type is an alias for `:string16`.

  ## Wire Format

      ┌─────────────────┬─────────────────────────────────────┐
      │  Length (uN)    │  UTF-8 Data (length bytes)          │
      │  little-endian  │                                     │
      └─────────────────┴─────────────────────────────────────┘

  ## Examples

      defmodule MyCodec do
        use GridCodec.Struct

        defcodec do
          field :id, :u64
          field :short_name, :string8   # Max 255 bytes
          field :description, :string16 # Max 65KB (default)
          field :content, :string32     # Max 4GB
        end
      end

  ## Encoding Rules

  - `nil` encodes as length = 0 (no data bytes)
  - Empty string `""` also encodes as length = 0
  - Strings are UTF-8 encoded (no null terminator)

  ## Performance Notes

  Prefer `:string8` for short, bounded strings (names, codes).
  This saves 1 byte per string vs `:string16`.
  """

  @behaviour GridCodec.Type

  @max_u8 255
  @max_u16 65_535
  @max_u32 4_294_967_295

  # ============================================================================
  # Type Callbacks (default is string16)
  # ============================================================================

  @impl true
  def size, do: :variable

  @impl true
  def alignment, do: 1

  @impl true
  def null_value, do: nil

  # ============================================================================
  # Encoding/Decoding for each variant
  # ============================================================================

  @doc """
  Encodes a string with u8 length prefix (max 255 bytes).
  """
  @spec encode8(binary() | nil) :: binary()
  def encode8(nil), do: <<0::8>>
  def encode8(""), do: <<0::8>>

  # Guard: fast check that value fits in u8 prefix (O(1))
  def encode8(value) when is_binary(value) and byte_size(value) <= @max_u8 do
    <<byte_size(value)::8, value::binary>>
  end

  def encode8(value) when is_binary(value) do
    raise ArgumentError, "String length #{byte_size(value)} exceeds u8 max (#{@max_u8})"
  end

  @doc """
  Encodes a string with u16 length prefix (max 65,535 bytes).
  """
  @spec encode16(binary() | nil) :: binary()
  def encode16(nil), do: <<0::little-16>>
  def encode16(""), do: <<0::little-16>>

  # Guard: fast check that value fits in u16 prefix (O(1))
  def encode16(value) when is_binary(value) and byte_size(value) <= @max_u16 do
    <<byte_size(value)::little-16, value::binary>>
  end

  def encode16(value) when is_binary(value) do
    raise ArgumentError, "String length #{byte_size(value)} exceeds u16 max (#{@max_u16})"
  end

  @doc """
  Encodes a string with u32 length prefix (max ~4GB).
  """
  @spec encode32(binary() | nil) :: binary()
  def encode32(nil), do: <<0::little-32>>
  def encode32(""), do: <<0::little-32>>

  # Guard: fast check that value fits in u32 prefix (O(1))
  def encode32(value) when is_binary(value) and byte_size(value) <= @max_u32 do
    <<byte_size(value)::little-32, value::binary>>
  end

  def encode32(value) when is_binary(value) do
    raise ArgumentError, "String length #{byte_size(value)} exceeds u32 max"
  end

  @doc """
  Default encode (u16 prefix).
  """
  @spec encode(binary() | nil) :: binary()
  def encode(value), do: encode16(value)

  @doc """
  Decodes a string with u8 length prefix.
  Returns `{value, rest}` tuple.
  """
  @spec decode8(binary()) :: {binary() | nil, binary()}
  def decode8(<<0::8, rest::binary>>), do: {nil, rest}

  # Pattern match handles size validation implicitly
  def decode8(<<len::8, value::binary-size(len), rest::binary>>) do
    {value, rest}
  end

  # Guard: explicit check for insufficient data (clearer error)
  def decode8(<<len::8, data::binary>>) when byte_size(data) < len do
    raise ArgumentError,
          "Insufficient data for string8: need #{len} bytes, got #{byte_size(data)}"
  end

  def decode8(binary) when byte_size(binary) < 1 do
    raise ArgumentError, "Insufficient data for string8 header"
  end

  @doc """
  Decodes a string with u16 length prefix.
  Returns `{value, rest}` tuple.
  """
  @spec decode16(binary()) :: {binary() | nil, binary()}
  def decode16(<<0::little-16, rest::binary>>), do: {nil, rest}

  # Pattern match handles size validation implicitly
  def decode16(<<len::little-16, value::binary-size(len), rest::binary>>) do
    {value, rest}
  end

  # Guard: explicit check for insufficient data (clearer error)
  def decode16(<<len::little-16, data::binary>>) when byte_size(data) < len do
    raise ArgumentError,
          "Insufficient data for string16: need #{len} bytes, got #{byte_size(data)}"
  end

  def decode16(binary) when byte_size(binary) < 2 do
    raise ArgumentError, "Insufficient data for string16 header"
  end

  @doc """
  Decodes a string with u32 length prefix.
  Returns `{value, rest}` tuple.
  """
  @spec decode32(binary()) :: {binary() | nil, binary()}
  def decode32(<<0::little-32, rest::binary>>), do: {nil, rest}

  # Pattern match handles size validation implicitly
  def decode32(<<len::little-32, value::binary-size(len), rest::binary>>) do
    {value, rest}
  end

  # Guard: explicit check for insufficient data (clearer error)
  def decode32(<<len::little-32, data::binary>>) when byte_size(data) < len do
    raise ArgumentError,
          "Insufficient data for string32: need #{len} bytes, got #{byte_size(data)}"
  end

  def decode32(binary) when byte_size(binary) < 4 do
    raise ArgumentError, "Insufficient data for string32 header"
  end

  @doc """
  Default decode (u16 prefix).
  """
  @spec decode(binary()) :: {binary() | nil, binary()}
  def decode(binary), do: decode16(binary)

  # ============================================================================
  # Type Callbacks (for AST generation)
  # ============================================================================

  @impl true
  def encode_ast(_field_name, _default, _endian, _data_var) do
    # String encoding is handled specially in the compiler
    # because strings go in the var-data section, not fixed block
    raise "String fields must be handled by the compiler's var-data section"
  end

  @impl true
  def decode_pattern_ast(_var, _endian) do
    # String decoding requires special handling
    raise "String fields must be handled by the compiler's var-data section"
  end

  @impl true
  def getter_ast(_offset, _endian, _payload_var) do
    # Strings don't have fixed offsets
    nil
  end

  @impl true
  def coerce_ast(var), do: gen_coerce_ast(var)

  @doc false
  def gen_coerce_ast(var) do
    quote do
      case unquote(var) do
        nil -> {:ok, nil}
        v when is_binary(v) -> {:ok, v}
        v when is_atom(v) -> {:ok, Atom.to_string(v)}
        v when is_number(v) -> {:ok, to_string(v)}
        v -> {:error, "expected string, got #{inspect(v)}"}
      end
    end
  end

  @doc false
  def gen_validate_ast(var, field, mod, type, max_length) do
    quote do
      case unquote(var) do
        nil ->
          :ok

        v when is_binary(v) and byte_size(v) <= unquote(max_length) ->
          :ok

        v when is_binary(v) ->
          raise GridCodec.ValidationError.out_of_range(
                  unquote(mod),
                  unquote(field),
                  unquote(type),
                  byte_size(v),
                  "string length <= #{unquote(max_length)} bytes"
                )

        v ->
          raise GridCodec.ValidationError.type_mismatch(
                  unquote(mod),
                  unquote(field),
                  unquote(type),
                  v,
                  "binary() or nil"
                )
      end
    end
  end

  if Code.ensure_loaded?(StreamData) do
    @impl true
    def generator, do: GridCodec.Generators.string16()
  end

  # ============================================================================
  # Constants
  # ============================================================================

  @doc "Maximum length for string8"
  def max_length8, do: @max_u8

  @doc "Maximum length for string16"
  def max_length16, do: @max_u16

  @doc "Maximum length for string32"
  def max_length32, do: @max_u32

  @doc "Default maximum length (string16)"
  def max_length, do: @max_u16
end

# ============================================================================
# String8 Type Module
# ============================================================================

defmodule GridCodec.Types.String8 do
  @moduledoc """
  Short string with u8 length prefix (max 255 bytes).

  Ideal for:
  - Names, codes, identifiers
  - Fixed-format strings (ISO codes, etc.)
  - Any string guaranteed to be < 256 bytes

  Saves 1 byte over string16 per field.
  """

  @behaviour GridCodec.Type

  @impl true
  def size, do: :variable

  @impl true
  def alignment, do: 1

  @impl true
  def null_value, do: nil

  @doc "Encodes string with u8 prefix"
  defdelegate encode(value), to: GridCodec.Types.String, as: :encode8

  @doc "Decodes string with u8 prefix"
  defdelegate decode(binary), to: GridCodec.Types.String, as: :decode8

  @impl true
  def encode_ast(_field_name, _default, _endian, _data_var) do
    raise "String8 fields must be handled by the compiler's var-data section"
  end

  @impl true
  def decode_pattern_ast(_var, _endian) do
    raise "String8 fields must be handled by the compiler's var-data section"
  end

  @impl true
  def getter_ast(_offset, _endian, _payload_var), do: nil

  @impl true
  def coerce_ast(var), do: GridCodec.Types.String.gen_coerce_ast(var)

  @impl true
  def validate_ast(var, field, mod) do
    GridCodec.Types.String.gen_validate_ast(
      var,
      field,
      mod,
      :string8,
      GridCodec.Types.String.max_length8()
    )
  end

  if Code.ensure_loaded?(StreamData) do
    @impl true
    def generator, do: GridCodec.Generators.string8()
  end
end

# ============================================================================
# String16 Type Module (default)
# ============================================================================

defmodule GridCodec.Types.String16 do
  @moduledoc """
  Medium string with u16 length prefix (max 65,535 bytes).

  This is the default string type. Suitable for:
  - Most text fields
  - Descriptions, comments
  - JSON blobs, small documents
  """

  @behaviour GridCodec.Type

  @impl true
  def size, do: :variable

  @impl true
  def alignment, do: 1

  @impl true
  def null_value, do: nil

  @doc "Encodes string with u16 prefix"
  defdelegate encode(value), to: GridCodec.Types.String, as: :encode16

  @doc "Decodes string with u16 prefix"
  defdelegate decode(binary), to: GridCodec.Types.String, as: :decode16

  @impl true
  def encode_ast(_field_name, _default, _endian, _data_var) do
    raise "String16 fields must be handled by the compiler's var-data section"
  end

  @impl true
  def decode_pattern_ast(_var, _endian) do
    raise "String16 fields must be handled by the compiler's var-data section"
  end

  @impl true
  def getter_ast(_offset, _endian, _payload_var), do: nil

  @impl true
  def coerce_ast(var), do: GridCodec.Types.String.gen_coerce_ast(var)

  @impl true
  def validate_ast(var, field, mod) do
    GridCodec.Types.String.gen_validate_ast(
      var,
      field,
      mod,
      :string16,
      GridCodec.Types.String.max_length16()
    )
  end

  if Code.ensure_loaded?(StreamData) do
    @impl true
    def generator, do: GridCodec.Generators.string16()
  end
end

# ============================================================================
# String32 Type Module
# ============================================================================

defmodule GridCodec.Types.String32 do
  @moduledoc """
  Large string with u32 length prefix (max ~4GB).

  Use sparingly. Suitable for:
  - Large documents
  - Base64-encoded binaries
  - Log aggregation

  ⚠️ Security: Always set max_bytes limits when parsing.
  """

  @behaviour GridCodec.Type

  @impl true
  def size, do: :variable

  @impl true
  def alignment, do: 1

  @impl true
  def null_value, do: nil

  @doc "Encodes string with u32 prefix"
  defdelegate encode(value), to: GridCodec.Types.String, as: :encode32

  @doc "Decodes string with u32 prefix"
  defdelegate decode(binary), to: GridCodec.Types.String, as: :decode32

  @impl true
  def encode_ast(_field_name, _default, _endian, _data_var) do
    raise "String32 fields must be handled by the compiler's var-data section"
  end

  @impl true
  def decode_pattern_ast(_var, _endian) do
    raise "String32 fields must be handled by the compiler's var-data section"
  end

  @impl true
  def getter_ast(_offset, _endian, _payload_var), do: nil

  @impl true
  def coerce_ast(var), do: GridCodec.Types.String.gen_coerce_ast(var)

  @impl true
  def validate_ast(var, field, mod) do
    GridCodec.Types.String.gen_validate_ast(
      var,
      field,
      mod,
      :string32,
      GridCodec.Types.String.max_length32()
    )
  end

  if Code.ensure_loaded?(StreamData) do
    @impl true
    def generator, do: GridCodec.Generators.string32()
  end
end
