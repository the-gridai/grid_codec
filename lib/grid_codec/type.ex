defmodule GridCodec.Type do
  @moduledoc """
  Behaviour for GridCodec field types.

  Each type module defines how to encode, decode, and access a specific
  data type in the binary format. This enables a modular, extensible
  type system.

  ## Implementing a Custom Type

  ```elixir
  defmodule MyApp.Types.Money do
    @behaviour GridCodec.Type

    @impl true
    def size, do: 8

    @impl true
    def alignment, do: 8

    @impl true
    def null_value, do: -9_223_372_036_854_775_808

    @impl true
    def encode_ast(field_name, default, endian, data_var) do
      quote do
        cents = Map.get(unquote(data_var), unquote(field_name), unquote(default))
        value = if is_nil(cents), do: unquote(__MODULE__.null_value()), else: cents
        <<value::signed-little-64>>
      end
    end

    # ... other callbacks
  end
  ```

  ## Type Categories

  ### Fixed-Size Types
  Types with constant byte size. These can be accessed at O(1) cost
  via compile-time offset calculation.

  | Type | Size | Alignment | Null Value |
  |------|------|-----------|------------|
  | `:u8` | 1 | 1 | 255 |
  | `:u16` | 2 | 2 | 65535 |
  | `:u32` | 4 | 4 | 4294967295 |
  | `:u64` | 8 | 8 | 18446744073709551615 |
  | `:i8` | 1 | 1 | -128 |
  | `:i16` | 2 | 2 | -32768 |
  | `:i32` | 4 | 4 | -2147483648 |
  | `:i64` | 8 | 8 | -9223372036854775808 |
  | `:f32` | 4 | 4 | NaN |
  | `:f64` | 8 | 8 | NaN |
  | `:uuid` | 16 | 1 | <<0::128>> |
  | `:bool` | 1 | 1 | 255 |

  ### Variable-Size Types
  Types that require length prefixes. These appear in the "var-data"
  section after groups.

  | Type | Prefix | Max Length |
  |------|--------|------------|
  | `:string8` | u8 | 255 bytes |
  | `:string` / `:string16` | u16 | 65535 bytes |
  | `:string32` | u32 | ~4GB |

  ## Alignment

  For optimal performance, fields can be aligned to their natural boundaries.
  A 64-bit integer starting at an offset divisible by 8 avoids unaligned access.
  The compiler handles padding automatically when `alignment/0 > 1`.
  """

  # ============================================================================
  # Callbacks
  # ============================================================================

  @doc """
  Returns the byte size of this type.

  For fixed-size types, return the exact byte count.
  For variable-size types, return `:variable`.

  ## Examples

      iex> GridCodec.Types.U64.size()
      8

      iex> GridCodec.Types.String.size()
      :variable
  """
  @callback size() :: pos_integer() | :variable

  @doc """
  Returns the alignment requirement in bytes.

  Fields are padded so their offset is divisible by this value.
  Most types align to their size (u64 aligns to 8, u32 to 4).
  Composite types like UUID may align to 1 (byte-aligned).

  ## Examples

      iex> GridCodec.Types.U64.alignment()
      8

      iex> GridCodec.Types.UUID.alignment()
      1
  """
  @callback alignment() :: pos_integer()

  @doc """
  Returns the null sentinel value for this type.

  GridCodec uses sentinel values to represent null/optional fields.
  For integers, this is typically the min/max value.
  For floats, NaN is used.

  Return `nil` if this type doesn't support null sentinels.

  ## Examples

      iex> GridCodec.Types.U64.null_value()
      18446744073709551615

      iex> GridCodec.Types.I64.null_value()
      -9223372036854775808
  """
  @callback null_value() :: term() | nil

  @doc """
  Generates the AST for encoding this field into a binary.

  The returned AST should be suitable for use inside a binary literal.

  ## Parameters

  - `field_name` - The atom name of the field
  - `default` - The default value if field is nil
  - `endian` - `:little` or `:big` byte order
  - `data_var` - The AST variable referencing the data map

  ## Returns

  Quoted expression for encoding this field.
  """
  @callback encode_ast(
              field_name :: atom(),
              default :: term(),
              endian :: :little | :big,
              data_var :: Macro.t()
            ) :: Macro.t()

  @doc """
  Generates the AST for the decode pattern match.

  The returned AST should be a binary pattern that binds the decoded
  value to the given variable.

  ## Parameters

  - `var` - The variable AST to bind the decoded value to
  - `endian` - `:little` or `:big` byte order

  ## Returns

  Quoted expression for use in a binary pattern match.
  """
  @callback decode_pattern_ast(var :: Macro.t(), endian :: :little | :big) :: Macro.t()

  @doc """
  Generates the AST for transforming a decoded value.

  Some types need post-processing after extraction from the binary.
  For example, bool needs to convert 0/1/255 to false/true/nil.

  The default implementation returns the variable unchanged.

  ## Parameters

  - `var` - The variable AST containing the decoded value

  ## Returns

  Quoted expression that transforms the value, or `var` if no transformation needed.
  """
  @callback decode_value_ast(var :: Macro.t()) :: Macro.t()

  @doc """
  Generates the AST for zero-copy field access.

  The returned AST should extract the field value from a binary at the
  given byte offset. For fixed-size types, this enables O(1) access
  without full decode.

  ## Parameters

  - `offset` - Byte offset from the start of the binary
  - `endian` - `:little` or `:big` byte order
  - `payload_var` - The AST variable referencing the payload binary

  ## Returns

  Quoted expression that extracts the value from the payload.
  Return `nil` if zero-copy access is not supported.
  """
  @callback getter_ast(
              offset :: non_neg_integer(),
              endian :: :little | :big,
              payload_var :: Macro.t()
            ) :: Macro.t() | nil

  @doc """
  Compares two decoded values for this type.

  Returns one of:
  - `:lt` when left < right
  - `:eq` when left == right
  - `:gt` when left > right

  This callback is optional. If not implemented, GridCodec falls back to
  Elixir term ordering.
  """
  @callback compare_values(left :: term(), right :: term()) :: :lt | :eq | :gt

  @doc """
  Returns a StreamData generator for this type.

  This callback is optional and only used when StreamData is available.
  Implement this to enable property-based testing for your custom types.

  ## Examples

      @impl true
      def generator do
        StreamData.integer(0..255)
      end

  The generator should produce values that are valid for encoding.
  """
  @callback generator() :: term()

  @optional_callbacks decode_value_ast: 1, generator: 0, compare_values: 2

  # ============================================================================
  # Type Registry
  # ============================================================================

  @doc """
  Returns the built-in type registry.

  Maps type atoms to their implementing modules.
  """
  @spec builtin_types() :: %{atom() => module()}
  def builtin_types do
    %{
      # Unsigned integers
      u8: GridCodec.Types.U8,
      u16: GridCodec.Types.U16,
      u32: GridCodec.Types.U32,
      u64: GridCodec.Types.U64,
      # Signed integers
      i8: GridCodec.Types.I8,
      i16: GridCodec.Types.I16,
      i32: GridCodec.Types.I32,
      i64: GridCodec.Types.I64,
      # Floats
      f32: GridCodec.Types.F32,
      f64: GridCodec.Types.F64,
      # Special types
      uuid: GridCodec.Types.UUID,
      uuid_string: GridCodec.Types.UUIDString,
      bool: GridCodec.Types.Bool,
      # Variable-length strings with length prefixes
      string: GridCodec.Types.String16,
      string8: GridCodec.Types.String8,
      string16: GridCodec.Types.String16,
      string32: GridCodec.Types.String32,
      # Composite types
      decimal: GridCodec.Types.Decimal,
      # Timestamps (i64)
      timestamp_us: GridCodec.Types.TimestampMicros,
      timestamp_ns: GridCodec.Types.TimestampNanos
    }
  end

  @doc """
  Looks up a type module by atom name.

  Returns `{:ok, module}` if found, or `{:error, :unknown_type}` if not.
  """
  @spec lookup(atom(), map()) :: {:ok, module()} | {:error, :unknown_type}
  def lookup(type_atom, custom_types \\ %{}) do
    all_types = Map.merge(builtin_types(), custom_types)

    case Map.fetch(all_types, type_atom) do
      {:ok, module} -> {:ok, module}
      :error -> {:error, :unknown_type}
    end
  end

  @doc """
  Returns the byte size for a type.

  Accepts either a type atom or module.
  """
  @spec size(atom() | module()) :: pos_integer() | :variable
  def size(type) when is_atom(type) do
    case lookup(type) do
      {:ok, module} -> module.size()
      {:error, _} -> raise ArgumentError, "Unknown type: #{inspect(type)}"
    end
  end

  @doc """
  Returns the alignment requirement for a type.
  """
  @spec alignment(atom() | module()) :: pos_integer()
  def alignment(type) when is_atom(type) do
    case lookup(type) do
      {:ok, module} -> module.alignment()
      {:error, _} -> raise ArgumentError, "Unknown type: #{inspect(type)}"
    end
  end

  @doc """
  Checks if a type is fixed-size.
  """
  @spec fixed_size?(atom() | module()) :: boolean()
  def fixed_size?(type) when is_atom(type) do
    size(type) != :variable
  end

  @doc """
  Calculates the padding needed to align to a boundary.

  ## Examples

      iex> GridCodec.Type.padding_for(5, 4)
      3

      iex> GridCodec.Type.padding_for(8, 8)
      0
  """
  @spec padding_for(non_neg_integer(), pos_integer()) :: non_neg_integer()
  def padding_for(offset, alignment) when alignment > 0 do
    rem_val = rem(offset, alignment)
    if rem_val == 0, do: 0, else: alignment - rem_val
  end

  @doc """
  Aligns an offset to the given boundary.

  ## Examples

      iex> GridCodec.Type.align(5, 4)
      8

      iex> GridCodec.Type.align(8, 8)
      8
  """
  @spec align(non_neg_integer(), pos_integer()) :: non_neg_integer()
  def align(offset, alignment) do
    offset + padding_for(offset, alignment)
  end

  @doc """
  Compares two values using type-specific comparison when available.

  Nil semantics are consistent across all types:
  - `nil` < any non-`nil`
  - `nil` == `nil`
  """
  @spec compare(module(), term(), term()) :: :lt | :eq | :gt
  def compare(type_module, left, right) when is_atom(type_module) do
    cond do
      left == nil and right == nil ->
        :eq

      left == nil ->
        :lt

      right == nil ->
        :gt

      function_exported?(type_module, :compare_values, 2) ->
        type_module.compare_values(left, right)

      left == right ->
        :eq

      left < right ->
        :lt

      true ->
        :gt
    end
  end
end
