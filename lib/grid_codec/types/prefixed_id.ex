defmodule GridCodec.Types.PrefixedId do
  @moduledoc """
  Macro-based prefixed identifier type: a u8 tag byte + 16-byte UUID.

  Prefixed IDs are self-describing on the wire — the tag byte identifies the
  entity type without full deserialization. In Elixir they appear as
  human-readable prefixed strings like `"user-550e8400-e29b-41d4-a716-446655440000"`.

  ## Wire Format

      Offset  Size  Field       Description
      ------  ----  ----------  ------------------------------------
      0       1     tag         u8 entity discriminator (constant per type)
      1       16    uuid        Raw UUID bytes (128 bits)

      Total: 17 bytes, Alignment: 1
      Null sentinel: <<0, 0::128>> (17 zero bytes — tag 0x00 is reserved)

  ## Defining a Prefixed ID Type

  ### Generated (recommended)

  Use the Mix generator for visible source code with full docs:

      mix grid_codec.gen.prefixed_id MyApp.Types.UserId --prefix user --tag 1

  ### Macro-only (compact)

      defmodule MyApp.Types.UserId do
        use GridCodec.Types.PrefixedId, prefix: "user", tag: 0x01
      end

  Then use in a codec:

      defmodule MyApp.Events.UserCreated do
        use GridCodec.Struct

        defcodec do
          field :user_id, MyApp.Types.UserId
          field :email, :string16
        end
      end

  ## Coercion (via `new/1`)

  | Input | Result |
  |-------|--------|
  | `"user-550e8400-e29b-..."` (prefixed) | Pass through after validation |
  | `"550e8400-e29b-..."` (plain UUID 36ch) | Auto-prefix |
  | `"550e8400e29b..."` (hex 32ch) | Format + prefix |
  | `<<16 bytes>>` (raw binary) | Format + prefix |
  | `nil` | `nil` (null sentinel on wire) |
  | `"mkt-550e8400-..."` (wrong prefix) | `{:error, ...}` |

  ## Ergonomics

      UserId.generate()                   # => "user-550e8400-..."
      UserId.from_uuid("550e8400-...")     # => "user-550e8400-..."
      UserId.to_uuid("user-550e8400-...")  # => "550e8400-..."
      UserId.valid?("user-550e8400-...")   # => true
      UserId.prefix()                      # => "user-"
      UserId.tag()                         # => 0x01

  ## DB-Level Binary Queries

  The tag byte sits at a fixed, known offset within the payload:

      -- Find events where user_id tag = 0x01
      WHERE get_byte(payload, <user_id_offset>) = 1
  """

  @doc """
  Defines a prefixed ID type.

  ## Options

  - `:prefix` — string prefix without trailing dash (e.g., `"user"`) **(required)**
  - `:tag` — u8 integer 1..254 **(required)**; 0x00 is reserved for null
  - `:schema` — schema name for `.grid` export placement (optional); overrides the
    default heuristic that places the type in the lowest referencing schema
  """
  defmacro __using__(opts) do
    prefix = Keyword.fetch!(opts, :prefix)
    tag = Keyword.fetch!(opts, :tag)
    schema_name = Keyword.get(opts, :schema)

    unless is_binary(prefix) and byte_size(prefix) > 0 do
      raise ArgumentError, ":prefix must be a non-empty string"
    end

    unless is_integer(tag) and tag >= 1 and tag <= 254 do
      raise ArgumentError, ":tag must be an integer 1..254 (0 is reserved for null)"
    end

    full_prefix = prefix <> "-"
    prefix_len = byte_size(full_prefix)

    quote do
      @behaviour GridCodec.Type

      @__prefix unquote(prefix)
      @__full_prefix unquote(full_prefix)
      @__prefix_len unquote(prefix_len)
      @__tag unquote(tag)
      @__schema_name unquote(schema_name)
      @__null_sentinel <<0, 0::128>>
      @__null_uuid <<0::128>>

      @before_compile GridCodec.Types.PrefixedId

      @doc false
      def __prefixed_id_meta__ do
        %{prefix: @__full_prefix, tag: @__tag, schema: @__schema_name}
      end

      # ================================================================
      # GridCodec.Type callbacks (always injected — compile-time AST)
      # ================================================================

      @impl GridCodec.Type
      def size, do: 17

      @impl GridCodec.Type
      def alignment, do: 1

      @impl GridCodec.Type
      def null_value, do: @__null_sentinel

      @impl GridCodec.Type
      def encode_ast(field_name, _default, _endian, data_var) do
        tag_val = @__tag
        prefix = @__full_prefix
        prefix_len = @__prefix_len
        null_sentinel = @__null_sentinel

        quote do
          case :maps.get(unquote(field_name), unquote(data_var), nil) do
            nil ->
              unquote(null_sentinel)

            <<_prefix::binary-size(unquote(prefix_len)), uuid_str::binary-size(36)>> = _v ->
              uuid_bytes = GridCodec.Types.UUIDString.parse_uuid_string!(uuid_str)
              <<unquote(tag_val)::8, uuid_bytes::binary-size(16)>>
          end :: binary - size(17)
        end
      end

      @impl GridCodec.Type
      def decode_pattern_ast(var, _endian) do
        quote do: unquote(var) :: binary - size(17)
      end

      @impl GridCodec.Type
      def decode_value_ast(var) do
        tag_val = @__tag
        null_sentinel = @__null_sentinel
        prefix = @__full_prefix

        quote do
          case unquote(var) do
            unquote(null_sentinel) ->
              nil

            <<unquote(tag_val)::8, uuid_bytes::binary-size(16)>> ->
              unquote(prefix) <> GridCodec.Types.UUIDString.format_uuid(uuid_bytes)

            <<_tag::8, uuid_bytes::binary-size(16)>> ->
              unquote(prefix) <> GridCodec.Types.UUIDString.format_uuid(uuid_bytes)
          end
        end
      end

      @impl GridCodec.Type
      def getter_ast(offset, _endian, payload_var) do
        tag_val = @__tag
        null_uuid = @__null_uuid
        prefix = @__full_prefix

        quote do
          <<_::binary-size(unquote(offset)), tag::8, uuid_bytes::binary-size(16), _::binary>> =
            unquote(payload_var)

          if tag == 0 and uuid_bytes == unquote(null_uuid) do
            nil
          else
            unquote(prefix) <> GridCodec.Types.UUIDString.format_uuid(uuid_bytes)
          end
        end
      end

      @impl GridCodec.Type
      def coerce_ast(var) do
        tag_val = @__tag
        prefix = @__full_prefix
        prefix_len = @__prefix_len

        quote do
          GridCodec.Types.PrefixedId.coerce(
            unquote(var),
            unquote(prefix),
            unquote(prefix_len),
            unquote(tag_val)
          )
        end
      end

      @impl GridCodec.Type
      def validate_ast(var, field_name, codec_module) do
        prefix = @__full_prefix
        prefix_len = @__prefix_len

        quote do
          case unquote(var) do
            nil ->
              :ok

            <<prefix::binary-size(unquote(prefix_len)), _uuid::binary-size(36)>>
            when prefix == unquote(prefix) ->
              :ok

            v ->
              raise GridCodec.ValidationError.invalid_format(
                      unquote(codec_module),
                      unquote(field_name),
                      :prefixed_id,
                      v,
                      "#{unquote(prefix)}<uuid> string"
                    )
          end
        end
      end

      if Code.ensure_loaded?(StreamData) do
        @impl GridCodec.Type
        def generator do
          prefix = @__full_prefix

          StreamData.map(StreamData.binary(length: 16), fn raw_bytes ->
            prefix <> GridCodec.Types.UUIDString.format_uuid(raw_bytes)
          end)
        end
      end
    end
  end

  # ================================================================
  # @before_compile — conditionally inject public helpers
  # ================================================================

  @doc false
  defmacro __before_compile__(env) do
    GridCodec.Types.PrefixedId.__maybe_inject_helpers__(env.module)
  end

  @doc false
  def __maybe_inject_helpers__(module) do
    if Module.defines?(module, {:generate, 0}) do
      quote do: :ok
    else
      __inject_helpers__(module)
    end
  end

  defp __inject_helpers__(module) do
    full_prefix = Module.get_attribute(module, :__full_prefix)
    prefix_len = Module.get_attribute(module, :__prefix_len)
    tag = Module.get_attribute(module, :__tag)

    default_intro =
      "GridCodec prefixed ID type: `#{full_prefix}<uuid>` (tag `#{tag}`)."

    standard_section = """

    ## Prefixed ID

    Wire format: 17 bytes (u8 tag + 16-byte UUID). Prefix: `#{full_prefix}` | Tag: `#{tag}`

    | Function | Description |
    |----------|-------------|
    | `generate/0` | Create a new prefixed ID with a random UUIDv4 |
    | `from_uuid/1` | Prepend the prefix to a plain UUID string |
    | `to_uuid/1` | Strip the prefix, returning the plain UUID |
    | `valid?/1` | Check if a value is a valid prefixed ID for this type |
    | `prefix/0` | Returns the string prefix (including trailing dash) |
    | `tag/0` | Returns the wire tag byte |
    """

    moduledoc_value =
      case Module.get_attribute(module, :moduledoc) do
        {_, false} -> false
        {_, existing} when is_binary(existing) -> existing <> "\n" <> standard_section
        _ -> default_intro <> "\n" <> standard_section
      end

    quote do
      @moduledoc unquote(moduledoc_value)

      @typedoc "A prefixed ID string of the form `#{unquote(full_prefix)}<uuid>`."
      @type t() :: String.t()

      @doc "Generates a new prefixed ID with a random UUIDv4."
      @spec generate() :: t()
      def generate do
        raw = GridCodec.Types.UUID.generate_v4()
        unquote(full_prefix) <> GridCodec.Types.UUIDString.format_uuid(raw)
      end

      @doc "Prepends the prefix to a plain UUID string."
      @spec from_uuid(String.t()) :: t()
      def from_uuid(uuid_str) when is_binary(uuid_str), do: unquote(full_prefix) <> uuid_str

      @doc "Strips the prefix, returning the plain UUID string."
      @spec to_uuid(t()) :: String.t()
      def to_uuid(<<prefix::binary-size(unquote(prefix_len)), uuid_str::binary>>)
          when prefix == unquote(full_prefix),
          do: uuid_str

      @doc "Returns `true` if the value is a valid prefixed ID for this type."
      @spec valid?(t() | term()) :: boolean()
      def valid?(<<prefix::binary-size(unquote(prefix_len)), uuid_str::binary-size(36)>>)
          when prefix == unquote(full_prefix) do
        GridCodec.Types.PrefixedId.valid_uuid_string?(uuid_str)
      end

      def valid?(_), do: false

      @doc "Returns the string prefix (including trailing dash)."
      @spec prefix() :: String.t()
      def prefix, do: unquote(full_prefix)

      @doc "Returns the wire tag byte."
      @spec tag() :: 0..254
      def tag, do: unquote(tag)
    end
  end

  # ================================================================
  # Shared runtime helpers (called from generated coerce_ast)
  # ================================================================

  @doc false
  def coerce(value, prefix, prefix_len, _tag) do
    case value do
      nil ->
        {:ok, nil}

      <<^prefix::binary-size(prefix_len), uuid_str::binary-size(36)>> ->
        if valid_uuid_string?(uuid_str) do
          {:ok, prefix <> uuid_str}
        else
          {:error, "invalid UUID in prefixed ID: #{inspect(value)}"}
        end

      v when is_binary(v) and byte_size(v) == 36 ->
        if valid_uuid_string?(v) do
          {:ok, prefix <> v}
        else
          {:error, "invalid UUID string: #{inspect(v)}"}
        end

      v when is_binary(v) and byte_size(v) == 32 ->
        try do
          raw = GridCodec.Types.UUIDString.parse_uuid_nodash!(v)
          {:ok, prefix <> GridCodec.Types.UUIDString.format_uuid(raw)}
        rescue
          _ -> {:error, "invalid hex UUID: #{inspect(v)}"}
        end

      <<_::binary-size(16)>> = raw ->
        {:ok, prefix <> GridCodec.Types.UUIDString.format_uuid(raw)}

      v when is_binary(v) ->
        {:error, "invalid prefixed ID: #{inspect(v)}"}

      v ->
        {:error, "expected prefixed ID string, UUID, or nil, got: #{inspect(v)}"}
    end
  end

  @doc false
  def valid_uuid_string?(
        <<a1, a2, a3, a4, a5, a6, a7, a8, ?-, b1, b2, b3, b4, ?-, c1, c2, c3, c4, ?-, d1, d2, d3,
          d4, ?-, e1, e2, e3, e4, e5, e6, e7, e8, e9, e10, e11, e12>>
      ) do
    hex?(a1) and hex?(a2) and hex?(a3) and hex?(a4) and
      hex?(a5) and hex?(a6) and hex?(a7) and hex?(a8) and
      hex?(b1) and hex?(b2) and hex?(b3) and hex?(b4) and
      hex?(c1) and hex?(c2) and hex?(c3) and hex?(c4) and
      hex?(d1) and hex?(d2) and hex?(d3) and hex?(d4) and
      hex?(e1) and hex?(e2) and hex?(e3) and hex?(e4) and
      hex?(e5) and hex?(e6) and hex?(e7) and hex?(e8) and
      hex?(e9) and hex?(e10) and hex?(e11) and hex?(e12)
  end

  def valid_uuid_string?(_), do: false

  defp hex?(c) when c >= ?0 and c <= ?9, do: true
  defp hex?(c) when c >= ?a and c <= ?f, do: true
  defp hex?(c) when c >= ?A and c <= ?F, do: true
  defp hex?(_), do: false
end
