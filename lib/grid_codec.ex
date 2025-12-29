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
  - **Alignment-aware**: Optional field alignment for cache-friendly access

  ## Quick Example

      defmodule MyApp.Events.OrderFilled do
        use GridCodec

        defcodec do
          field :order_id, :uuid
          field :price, :u64
          field :quantity, :u32
          field :timestamp, :i64
        end
      end

      # Encoding
      event = %{
        order_id: <<1::128>>,
        price: 15000,
        quantity: 100,
        timestamp: System.system_time(:microsecond)
      }
      binary = MyApp.Events.OrderFilled.encode(event)

      # Zero-copy field access (O(1) for fixed-size types)
      env = MyApp.Events.OrderFilled.wrap(binary)
      order_id = MyApp.Events.OrderFilled.get(env, :order_id)

      # Full decode when needed
      {:ok, decoded} = MyApp.Events.OrderFilled.decode(binary)

  ## Wire Format

  GridCodec messages are laid out in three sections:

      ┌─────────────────────────────────────────────────────────┐
      │ Fixed Block                                             │
      │   All fixed-size fields in declaration order            │
      ├─────────────────────────────────────────────────────────┤
      │ Groups Section                                          │
      │   Header (8 bytes) + Entries for each group             │
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

  ### Variable-Size Types

  | Type | Prefix | Max Size | Description |
  |------|--------|----------|-------------|
  | `:string` | u16 | 65535 | UTF-8 string |

  ## Groups

  Groups enable repeating collections of fixed-size entries:

      defcodec do
        field :order_id, :uuid

        group :fills, entry_encoder: &encode_fill/1, entry_decoder: &decode_fill/1 do
          # Documentation for entry structure
          field :price, :u64
          field :quantity, :u32
        end
      end

  Groups use an 8-byte header (numInGroup u32 + blockLength u32) followed
  by N fixed-size entries. See `GridCodec.Group` for iteration APIs.

  ## Zero-Copy Design

  BEAM binaries > 64 bytes are reference-counted and shared across processes.
  GridCodec leverages this via:

  1. **Wrap without decode**: `wrap/1` creates an envelope holding a binary reference
  2. **O(1) field access**: `get/2` uses compile-time offsets for sub-binary extraction
  3. **Lazy iteration**: Groups stream entries without copying the underlying binary

  This is ideal for fan-out scenarios like Phoenix.PubSub broadcasts.

  ## Custom Types

  Register custom types via the `:types` option:

      defmodule MyApp.Types.Money do
        @behaviour GridCodec.Type
        # ... implement callbacks
      end

      defmodule MyCodec do
        use GridCodec, types: [money: MyApp.Types.Money]

        defcodec do
          field :price, :money
        end
      end

  See `GridCodec.Type` for the behaviour specification.
  """

  @doc """
  Defines a codec module with the GridCodec DSL.

  When you `use GridCodec`, the `defcodec/1` macro becomes available
  for defining your binary schema.

  ## Options

  - `:template_id` - Unique message type identifier for dispatch (default: 0)
  - `:schema_id` - Schema/application namespace identifier (default: 0)
  - `:version` - Schema version for evolution (default: 1)
  - `:endian` - Byte order, `:little` or `:big` (default: `:little`)
  - `:align` - Enable natural field alignment for performance (default: false)
  - `:types` - Keyword list of custom type modules (default: [])

  ## Message Framing

  GridCodec supports two encoding modes:

  - `encode/1` - Raw payload only (for internal use or custom framing)
  - `encode!/1` - Includes 8-byte header (for dispatch/routing)

  The header contains: `block_length | template_id | schema_id | version`

  ## Example

      defmodule MyApp.Events.OrderFilled do
        use GridCodec,
          template_id: 1,    # Unique within schema
          schema_id: 100,    # Your app's schema namespace
          version: 1

        defcodec do
          field :id, :u64
          field :name, :string
        end
      end

      # Register for dispatch
      GridCodec.Dispatch.register(MyApp.Events.OrderFilled)

      # Encode with header
      framed = MyApp.Events.OrderFilled.encode!(%{id: 1, name: "test"})

      # Dispatch to correct decoder
      {:ok, decoded, _codec} = GridCodec.Dispatch.decode(framed)
  """
  defmacro __using__(opts \\ []) do
    quote do
      import GridCodec, only: [defcodec: 1, field: 2, field: 3, group: 2, group: 3]
      @gridcodec_opts unquote(opts)
      Module.register_attribute(__MODULE__, :gridcodec_fields, accumulate: true)
      Module.register_attribute(__MODULE__, :gridcodec_groups, accumulate: true)
    end
  end

  @doc """
  Defines the codec schema.

  Inside the `defcodec` block, use `field/2`, `field/3`, and `group/2`
  to define your binary structure.

  ## Example

      defcodec do
        field :order_id, :uuid
        field :price, :u64, default: 0
        field :notes, :string

        group :items, entry_encoder: &encode_item/1, entry_decoder: &decode_item/1 do
          field :sku_id, :uuid
          field :qty, :u32
        end
      end
  """
  defmacro defcodec(do: block) do
    quote do
      # Collect field definitions
      unquote(block)

      # Generate the codec implementation
      @before_compile GridCodec.Compiler
    end
  end

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
    - `:since` - Schema version when this field was added (for documentation
      and schema evolution). Must be <= codec's version.

  ## Schema Evolution

  Use `:since` to document when fields were added:

      defmodule MyCodec do
        use GridCodec, version: 2

        defcodec do
          field :id, :u64               # Original field (version 1)
          field :count, :u32            # Original field (version 1)
          field :status, :u8, since: 2  # Added in version 2
        end
      end

  When decoding older messages (via `decode!/1`), fields added in newer
  versions use their type's null_value if the binary is too short.

  ## Examples

      field :user_id, :uuid
      field :count, :u32, default: 0
      field :price, :u64, presence: :required
      field :description, :string
      field :version, :u8, presence: :constant, value: 1
      field :new_feature, :bool, since: 2  # Added in schema v2
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

  Groups use an 8-byte header followed by fixed-size entries:

      ┌────────────────────────┬────────────────────────┐
      │  numInGroup (u32 LE)   │  blockLength (u32 LE)  │
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
end
