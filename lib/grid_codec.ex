defmodule GridCodec do
  @moduledoc """
  High-performance binary codec for BEAM/Elixir with zero-copy field access.

  GridCodec generates efficient binary encoders/decoders at compile time,
  optimized for BEAM's sub-binary sharing. This means when you broadcast
  an encoded message to many processes, they all share the same underlying
  binary—no copies.

  ## Features

  - **Zero-copy field access**: Read fields directly from binary without full decode
  - **Sub-binary sharing**: One encode, many readers with no memory copies
  - **Compile-time code generation**: No runtime reflection overhead
  - **Fixed-size optimization**: Known field offsets for O(1) access
  - **Variable-length support**: Groups and strings with efficient iteration
  - **Struct-based API**: Natural Elixir struct syntax

  ## Quick Example

      defmodule MyApp.Events.OrderFilled do
        use GridCodec.Struct, template_id: 1, schema_id: 100

        defcodec do
          field :order_id, :uuid
          field :price, :u64
          field :quantity, :u32
          field :timestamp, :timestamp_us
        end
      end

      # Create a struct
      order = %MyApp.Events.OrderFilled{
        order_id: <<1::128>>,
        price: 15000,
        quantity: 100,
        timestamp: DateTime.utc_now()
      }

      # Encode (includes 8-byte header by default)
      binary = MyApp.Events.OrderFilled.encode(order)

      # Decode (expects header by default)
      {:ok, decoded} = MyApp.Events.OrderFilled.decode(binary)

      # Zero-copy field access (O(1) for fixed-size types)
      require MyApp.Events.OrderFilled, as: Order

      # get macro (inline binary pattern with null handling)
      price = Order.get(binary, :price)

      # Or: match macro for multi-field extraction (raw bytes, no null check)
      case binary do
        Order.match(price: p, quantity: q) -> {p, q}
      end

      # Dispatch via GridCodec (same binary format)
      {:ok, decoded} = GridCodec.decode(binary)

      # Payload only (no header) - use when you don't need dispatch
      payload = MyApp.Events.OrderFilled.encode(order, header: false)
      {:ok, decoded} = MyApp.Events.OrderFilled.decode(payload, header: false)

  ## Field Access Methods

  GridCodec provides two macros for zero-copy field access:

  | Method | Speed | Use Case |
  |--------|-------|----------|
  | `get/2` macro | ~70M ips | Single-field access, **returns nil for nulls** |
  | `match/1` macro | ~70M ips | Multi-field extraction, **returns raw sentinel values** |

  ```elixir
  require MyCodec

  # get macro - single-field access with null handling
  price = MyCodec.get(binary, :price)  # Returns nil if field is null

  # match macro - multi-field extraction (⚠️ returns raw bytes, NOT nil)
  case binary do
    MyCodec.match(price: p, qty: q) -> {p, q}  # p is sentinel value if null!
  end
  ```

  ### ⚠️ Important: `match` vs `get` for Nullable Fields

  The `match` macro extracts raw binary values. For nullable fields, this means:
  - **`get/2`**: Returns `nil` if field is null ✓
  - **`match/1`**: Returns the raw sentinel value (e.g., `0xFFFFFFFF` for u32) ⚠️

  ```elixir
  # For a struct with price: nil encoded:
  MyCodec.get(binary, :price)           # => nil
  MyCodec.match(price: p) -> p          # => 0xFFFFFFFF (sentinel!)
  ```

  Attempting to match on literal `nil` will raise a **compile-time error**:

  ```elixir
  # This raises CompileError!
  MyCodec.match(price: nil)
  ```

  Use `match` for performance-critical paths where you know fields are non-null,
  or when you need to extract multiple fields at once. Use `get` when you need
  null-safe access.

  ## Wire Format

  GridCodec messages are laid out in three sections:

      ┌─────────────────────────────────────────────────────────┐
      │ Fixed Block                                             │
      │   All fixed-size fields in declaration order            │
      ├─────────────────────────────────────────────────────────┤
      │ Groups Section                                          │
      │   Header (4 bytes: blockLength u16 + numInGroup u16)    │
      │   + Entries for each group                              │
      ├─────────────────────────────────────────────────────────┤
      │ Var-Data Section                                        │
      │   Length-prefixed strings/bytes                         │
      └─────────────────────────────────────────────────────────┘

  ## Field Types

  ### Fixed-Size Types

  | Type | Size | Null Value | Description |
  |------|------|------------|-------------|
  | `:u8` | 1 | 255 | Unsigned 8-bit |
  | `:u16` | 2 | 65535 | Unsigned 16-bit |
  | `:u32` | 4 | 4294967295 | Unsigned 32-bit |
  | `:u64` | 8 | 2^64-1 | Unsigned 64-bit |
  | `:i8` | 1 | -128 | Signed 8-bit |
  | `:i16` | 2 | -32768 | Signed 16-bit |
  | `:i32` | 4 | -2^31 | Signed 32-bit |
  | `:i64` | 8 | -2^63 | Signed 64-bit |
  | `:f32` | 4 | NaN | IEEE 754 single |
  | `:f64` | 8 | NaN | IEEE 754 double |
  | `:uuid` | 16 | zero | Binary UUID |
  | `:bool` | 1 | 255 | Boolean (0/1/255) |
  | `:timestamp_us` | 8 | 0 | Microsecond timestamp |

  ### Variable-Size Types

  | Type | Prefix | Max Size | Description |
  |------|--------|----------|-------------|
  | `:string8` | u8 | 255 | Short strings |
  | `:string` / `:string16` | u16 | 65535 | UTF-8 string (default) |
  | `:string32` | u32 | ~4GB | Large text |

  ## Groups

  Groups enable repeating collections of fixed-size entries:

      defmodule MyCodec do
        use GridCodec.Struct, template_id: 1, schema_id: 100

        defcodec do
          field :order_id, :uuid

          group :fills, entry_encoder: &encode_fill/1, entry_decoder: &decode_fill/1 do
            field :price, :u64
            field :quantity, :u32
          end
        end

        defp encode_fill(%{price: p, quantity: q}), do: <<p::little-64, q::little-32>>
        defp decode_fill(<<p::little-64, q::little-32>>), do: {:ok, %{price: p, quantity: q}}
      end

  Groups use a 4-byte header (blockLength u16 + numInGroup u16) followed
  by N fixed-size entries. See `GridCodec.Group` for iteration APIs.

  ## Zero-Copy Design

  BEAM binaries > 64 bytes are reference-counted and shared across processes.
  GridCodec leverages this via:

  1. **O(1) field access**: `get/2` macro uses compile-time offsets for sub-binary extraction
  2. **Sub-binary sharing**: Extracted fields share memory with the original binary
  3. **Lazy iteration**: Groups stream entries without copying the underlying binary

  This is ideal for fan-out scenarios like Phoenix.PubSub broadcasts.

  ## Custom Types

  Register custom types via the `:types` option:

      defmodule MyApp.Types.Money do
        @behaviour GridCodec.Type
        # ... implement callbacks
      end

      defmodule MyCodec do
        use GridCodec.Struct, types: [money: MyApp.Types.Money]

        defcodec do
          field :price, :money
        end
      end

  See `GridCodec.Type` for the behaviour specification.
  """

  # ============================================================================
  # Field and Group Macros (used by GridCodec.Struct)
  # ============================================================================

  @doc """
  Defines a field in the codec.

  ## Arguments

  - `name` - Atom field name
  - `type` - Field type (see module docs for supported types)
  - `opts` - Optional keyword list:
    - `:default` - Default value for encoding when field is nil
    - `:presence` - Field presence mode (default: `:optional`)
      - `:optional` - Field can be nil (uses null sentinel)
      - `:required` - Field must have a value (raises on nil)
      - `:constant` - Field has constant value (must specify `:value`)
    - `:value` - Constant value (required when `presence: :constant`)
    - `:since` - Schema version when this field was added

  ## Examples

      field :user_id, :uuid
      field :count, :u32, default: 0
      field :price, :u64, presence: :required
      field :description, :string
      field :version, :u8, presence: :constant, value: 1
  """
  defmacro field(name, type, opts \\ []) do
    quote do
      @gridcodec_fields {unquote(name), unquote(type), unquote(opts)}
    end
  end

  @doc """
  Defines a repeating group of fields.

  Groups encode variable-length collections where each entry has
  the same fixed-size structure.

  ## Arguments

  - `name` - Atom group name
  - `opts` - Keyword options:
    - `:entry_encoder` - Function `(entry :: map) -> binary` (required for encoding)
    - `:entry_decoder` - Function `(binary) -> {:ok, map}` (required for decoding)
  - `block` - Field definitions for documentation (not used at runtime)

  ## Wire Format

  Groups use a 4-byte header followed by fixed-size entries:

      ┌────────────────────────┬────────────────────────┐
      │  blockLength (u16 LE)  │  numInGroup (u16 LE)   │
      └────────────────────────┴────────────────────────┘
      │  Entry[0] ... Entry[N-1]                        │
      └─────────────────────────────────────────────────┘

  ## Example

      defp encode_fill(%{price: p, qty: q}), do: <<p::little-64, q::little-32>>
      defp decode_fill(<<p::little-64, q::little-32>>), do: {:ok, %{price: p, qty: q}}

      defcodec do
        field :order_id, :uuid

        group :fills, entry_encoder: &encode_fill/1, entry_decoder: &decode_fill/1 do
          field :price, :u64
          field :qty, :u32
        end
      end

  ## Iteration

  Decoded groups support lazy iteration via `GridCodec.Group`:

      {:ok, data} = MyCodec.decode(binary)

      data.fills
      |> GridCodec.Group.stream()
      |> Stream.filter(&(&1.qty > 100))
      |> Enum.take(10)
  """
  defmacro group(name, opts \\ [], do: block) do
    quote do
      @gridcodec_groups {unquote(name), unquote(Macro.escape(block)), unquote(opts)}
    end
  end

  # ============================================================================
  # Top-Level Struct API
  # ============================================================================
  # These functions delegate to the registry for struct codec dispatch.
  # In production builds, the consolidated registry provides optimized
  # pattern-match dispatch. In development, runtime discovery is used.

  @doc """
  Encode a GridCodec struct to binary.

  By default includes an 8-byte header for dispatch via `GridCodec.decode/1`.

  ## Options

  - `:header` - Include header (default: `true`)

  ## Examples

      order = %MyApp.Order{id: <<1::128>>, price: 100, quantity: 5}

      # With header (default)
      binary = GridCodec.encode(order)

      # Without header - payload only
      payload = GridCodec.encode(order, header: false)
  """
  defdelegate encode(struct), to: GridCodec.Registry
  defdelegate encode(struct, opts), to: GridCodec.Registry

  @doc """
  Decode a binary, dispatching to the correct struct codec.

  By default expects an 8-byte header for module dispatch.

  ## Options

  - `:header` - Expect header (default: `true`)
  - `:module` - Required when `header: false` to specify the codec module

  ## Examples

      # With header (default)
      {:ok, %MyApp.Order{}} = GridCodec.decode(binary)

      # Without header - must specify module
      {:ok, %MyApp.Order{}} = GridCodec.decode(payload, header: false, module: MyApp.Order)
  """
  defdelegate decode(binary), to: GridCodec.Registry
  defdelegate decode(binary, opts), to: GridCodec.Registry

  # ============================================================================
  # Generic Field Access with Field Specs
  # ============================================================================

  @doc """
  Extract a field from a binary using a field spec.

  The field spec is generated at compile time by the `field/1` macro in each codec:

      require MyCodec
      value = GridCodec.get(binary, MyCodec.field(:price))

  This enables efficient field access with compile-time offset calculation
  and runtime type dispatch.

  ## Examples

      # With field spec macro
      require ExampleApp.Events.OrderCreated, as: Order
      price = GridCodec.get(binary, Order.field(:price))

      # The field/1 macro expands to a tuple at compile time:
      # Order.field(:price) => {GridCodec.Types.U64, 16, :little}
      # GridCodec.get then dispatches to the type's get_value/3

  ## Performance

  This approach is slower than the direct `MyCodec.get(binary, :field)` macro
  due to runtime type dispatch. For maximum performance in hot paths, use
  the `get` or `match` macros with `require`.
  """
  @spec get(binary(), {module(), non_neg_integer(), :little | :big}) :: term()
  def get(binary, {type_module, offset, endian}) when is_binary(binary) do
    type_module.get_value(binary, offset, endian)
  end

  def get(_binary, {:variable, field_name}) do
    raise ArgumentError,
          "Variable-length field #{inspect(field_name)} requires full decode. " <>
            "Use MyCodec.decode/1 instead."
  end

  def get(_binary, {:group, group_name}) do
    raise ArgumentError,
          "Group #{inspect(group_name)} requires full decode. " <>
            "Use MyCodec.decode/1 instead."
  end

  @doc """
  Inspects a GridCodec binary for debugging and operational diagnostics.

  Delegates to `GridCodec.BinaryInspector.inspect/2`.
  """
  @spec inspect_binary(binary(), keyword()) ::
          {:ok, GridCodec.BinaryInspector.inspect_result()} | {:error, term()}
  defdelegate inspect_binary(binary, opts \\ []), to: GridCodec.BinaryInspector, as: :inspect

  @type compare_op :: :< | :<= | :> | :>= | :== | :!=

  @doc """
  Compares a field from `binary` against either a literal value or another binary.

  ## Options

  - `:rhs` - Comparison source for `rhs`:
    - `:value` (default): compare against literal decoded value
    - `:binary`: extract the same field from `rhs` binary and compare field-to-field

  ## Examples

      require MyCodec
      spec = MyCodec.field(:price)

      # Compare against literal
      GridCodec.compare(binary, spec, :>, 1000)

      # Compare field from two binaries
      GridCodec.compare(binary_a, spec, :>, binary_b, rhs: :binary)
  """
  @spec compare(
          binary(),
          {module(), non_neg_integer(), :little | :big} | {:variable, atom()} | {:group, atom()},
          compare_op(),
          term(),
          keyword()
        ) :: boolean()
  def compare(binary, field_spec, op, rhs, opts \\ [])

  def compare(binary, {type_module, _offset, _endian} = field_spec, op, rhs, opts)
      when is_binary(binary) do
    lhs_value = get(binary, field_spec)

    rhs_value =
      if Keyword.get(opts, :rhs, :value) == :binary do
        if is_binary(rhs) do
          get(rhs, field_spec)
        else
          raise ArgumentError, "compare with rhs: :binary expects rhs to be a binary"
        end
      else
        rhs
      end

    compare_values(type_module, lhs_value, op, rhs_value)
  end

  def compare(_binary, {:variable, field_name}, _op, _rhs, _opts) do
    raise ArgumentError,
          "Variable-length field #{inspect(field_name)} requires full decode. " <>
            "Use MyCodec.decode/1 and compare decoded values."
  end

  def compare(_binary, {:group, group_name}, _op, _rhs, _opts) do
    raise ArgumentError,
          "Group #{inspect(group_name)} requires full decode. " <>
            "Use MyCodec.decode/1 and compare decoded values."
  end

  @doc """
  Compares the same field between two binaries.

  Convenience wrapper around `compare/5` with `rhs: :binary`.
  """
  @spec compare_binaries(
          binary(),
          {module(), non_neg_integer(), :little | :big} | {:variable, atom()} | {:group, atom()},
          compare_op(),
          binary()
        ) :: boolean()
  def compare_binaries(lhs_binary, field_spec, op, rhs_binary) do
    compare(lhs_binary, field_spec, op, rhs_binary, rhs: :binary)
  end

  @doc false
  @spec compare_values(module(), term(), compare_op(), term()) :: boolean()
  def compare_values(type_module, left, op, right) do
    result = GridCodec.Type.compare(type_module, left, right)

    case op do
      :< -> result == :lt
      :<= -> result in [:lt, :eq]
      :> -> result == :gt
      :>= -> result in [:gt, :eq]
      :== -> result == :eq
      :!= -> result != :eq
      _ -> raise ArgumentError, "unsupported compare operator: #{inspect(op)}"
    end
  end
end
