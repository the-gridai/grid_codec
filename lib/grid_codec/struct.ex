defmodule GridCodec.Struct do
  @moduledoc """
  Integrates GridCodec with Elixir structs.

  When you `use GridCodec.Struct`, the `defcodec/1` macro becomes available
  and automatically generates both the struct definition and the codec
  implementation.

  ## Features

  - **Auto-generated `defstruct`**: Field definitions in `defcodec` become struct fields
  - **Enforced keys**: Fields with `presence: :required` are added to `@enforce_keys`
  - **Compile-time registration**: Codecs register for dispatch via template_id/schema_id
  - **Zero-copy access**: Same `wrap/1` and `get/2` APIs for efficient field access

  ## Quick Example

      defmodule MyApp.Order do
        use GridCodec.Struct, template_id: 1, schema_id: 100

        defcodec do
          field :id, :uuid, presence: :required
          field :price, :u64, default: 0
          field :quantity, :u32
        end
      end

      # Creates:
      # - %MyApp.Order{} struct with @enforce_keys [:id]
      # - MyApp.Order.encode/1, decode/1, encode!/1, decode!/1
      # - Registered for dispatch via GridCodec.decode/1

  ## Options

  - `:template_id` - Unique message type identifier (default: hash of module name)
  - `:schema_id` - Schema namespace identifier (default: 0)
  - `:version` - Schema version (default: 1)
  - `:endian` - Byte order, `:little` or `:big` (default: `:little`)
  - `:align` - Enable field alignment (default: false)
  - `:types` - Custom type modules (default: [])

  ## Usage

      defmodule MyApp.Trade do
        use GridCodec.Struct,
          template_id: 2,
          schema_id: 100

        defcodec do
          field :trade_id, :uuid, presence: :required
          field :price, :u64
          field :quantity, :u32
          field :side, :u8, default: 0
        end
      end

      # Create and encode
      trade = %MyApp.Trade{
        trade_id: <<1::128>>,
        price: 15000,
        quantity: 100
      }

      # Encode with header (for dispatch)
      binary = GridCodec.encode(trade)
      # or: binary = MyApp.Trade.encode!(trade)

      # Decode (dispatch finds correct module)
      {:ok, %MyApp.Trade{}} = GridCodec.decode(binary)
      # or: {:ok, %MyApp.Trade{}} = MyApp.Trade.decode!(binary)

      # Zero-copy field access
      env = MyApp.Trade.wrap(payload)
      price = MyApp.Trade.get(env, :price)

  ## Template ID

  If not specified, `template_id` defaults to a hash of the module name:

      # These are equivalent:
      use GridCodec.Struct, template_id: :erlang.phash2(MyApp.Order) &&& 0xFFFF
      use GridCodec.Struct  # auto-generates template_id

  For production use, explicit template_ids are recommended for stability.
  """

  @doc false
  defmacro __using__(opts \\ []) do
    quote do
      import GridCodec.Struct, only: [defcodec: 1]
      import GridCodec, only: [field: 2, field: 3, group: 2, group: 3]

      @gridcodec_opts unquote(opts)
      @gridcodec_is_struct true

      Module.register_attribute(__MODULE__, :gridcodec_fields, accumulate: true)
      Module.register_attribute(__MODULE__, :gridcodec_groups, accumulate: true)
    end
  end

  @doc """
  Defines the codec schema and generates both `defstruct` and codec functions.

  Inside the `defcodec` block, use `field/2`, `field/3`, and `group/2`
  to define your struct fields and binary layout.

  ## Example

      defcodec do
        field :id, :uuid, presence: :required
        field :price, :u64, default: 0
        field :quantity, :u32
      end

  ## Generated Struct

  The `defstruct` is generated automatically with:
  - Field names from `field` declarations
  - Default values from the `:default` option
  - Fields with `presence: :required` added to `@enforce_keys`
  - Fields with `presence: :constant` get their `:value` as default

  ## Generated Functions

  - `encode/1` - Encodes struct to binary (payload only)
  - `encode!/1` - Encodes struct with 8-byte header (for dispatch)
  - `decode/1` - Decodes binary payload to struct
  - `decode!/1` - Decodes framed binary (validates header)
  - `wrap/1` - Wraps binary for zero-copy access
  - `get/2` - Gets field from wrapped binary
  - `__schema__/0` - Returns schema metadata
  - `__template_id__/0` - Returns template ID
  - `__schema_id__/0` - Returns schema ID
  - `__fields__/0` - Returns list of field names
  """
  defmacro defcodec(do: block) do
    quote do
      # Collect field definitions
      unquote(block)

      # Generate the struct and codec implementation
      @before_compile GridCodec.Struct.Compiler
    end
  end
end
