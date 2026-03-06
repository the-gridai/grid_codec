defmodule GridCodec.Types.UUID do
  @moduledoc """
  128-bit UUID (Universally Unique Identifier) type.

  Encodes UUIDs as 16 raw bytes. This is more efficient than string
  representation (36 bytes) and allows for zero-copy sub-binary access.

  ## Examples

      defmodule MyCodec do
        use GridCodec.Struct

        defcodec do
          field :id, :uuid
          field :parent_id, :uuid
        end
      end

      # With raw UUID bytes
      id = :crypto.strong_rand_bytes(16)
      {:ok, binary} = MyCodec.encode(%MyCodec{id: id, parent_id: <<0::128>>})

      # Zero-copy access returns a sub-binary reference
      require MyCodec
      id = MyCodec.get(binary, :id)  # Sub-binary, no copy!

  ## Wire Format

      Offset  Size  Description
      ──────  ────  ───────────
      0       16    Raw UUID bytes (128 bits)

  ## UUID Formats

  UUIDs can come in different formats. GridCodec stores them as raw bytes:

      # String format (NOT stored this way)
      "550e8400-e29b-41d4-a716-446655440000"

      # Raw bytes (16 bytes, stored this way)
      <<85, 14, 132, 0, 226, 155, 65, 212, 167, 22, 68, 102, 85, 68, 0, 0>>

  ## Converting from String UUIDs

  If you have string UUIDs, convert them before encoding:

      # Using the `uuid` package
      {:ok, binary} = UUID.dump("550e8400-e29b-41d4-a716-446655440000")

      # Or manually
      "550e8400-e29b-41d4-a716-446655440000"
      |> String.replace("-", "")
      |> Base.decode16!(case: :mixed)

  ## Zero-Copy Benefits

  The UUID type is particularly suited for GridCodec's zero-copy access.
  When you call `MyCodec.get(binary, :uuid_field)`, you receive a sub-binary
  reference to the original payload—no memory allocation or copy occurs.

  This is ideal for high-throughput scenarios where you need to extract
  IDs for routing or filtering without full message decode.

  ## Generating UUIDs

      # Random (v4) — unique per call
      GridCodec.Types.UUID.generate_v4()

      # Deterministic (v5) — same inputs always produce the same UUID
      GridCodec.Types.UUID.generate_v5(:dns, "example.com")

      # Time-sortable (v7) — lexicographically ordered by creation time
      GridCodec.Types.UUID.generate_v7()
  """

  @behaviour GridCodec.Type

  # All zeros represents null UUID
  @null_uuid <<0::128>>

  @impl true
  def size, do: 16

  @impl true
  def alignment, do: 1

  @impl true
  def null_value, do: @null_uuid

  @impl true
  def encode_ast(field_name, _default, _endian, data_var) do
    null_uuid = @null_uuid

    # Handle nil by encoding as all-zeros (null UUID)
    quote do
      :maps.get(unquote(field_name), unquote(data_var), nil) || unquote(null_uuid) ::
        binary - size(16)
    end
  end

  @impl true
  def decode_pattern_ast(var, _endian) do
    # UUIDs are endian-independent (just bytes)
    quote do: unquote(var) :: binary - size(16)
  end

  @impl true
  def decode_value_ast(var) do
    null = @null_uuid

    # Convert all-zeros to nil for proper null handling
    # Use equality comparison (fast) instead of pattern match with pin (slow!)
    quote do
      if unquote(var) == unquote(null), do: nil, else: unquote(var)
    end
  end

  @impl true
  def getter_ast(offset, _endian, payload_var) do
    null = @null_uuid

    # Returns a sub-binary reference (zero-copy!) or nil for null UUID
    quote do
      <<_::binary-size(unquote(offset)), value::binary-size(16), _::binary>> =
        unquote(payload_var)

      if value == unquote(null), do: nil, else: value
    end
  end

  @doc """
  Extracts a UUID from a binary at the given offset.
  """
  def get_value(binary, offset, _endian) when is_binary(binary) do
    <<_::binary-size(offset), value::binary-size(16), _::binary>> = binary
    if value == @null_uuid, do: nil, else: value
  end

  # Standard namespace UUIDs (RFC 4122 Appendix C)
  @ns_dns <<0x6BA7B810::32, 0x9DAD::16, 0x11D1::16, 0x80::8, 0xB4::8, 0x00C04FD430C8::48>>
  @ns_url <<0x6BA7B811::32, 0x9DAD::16, 0x11D1::16, 0x80::8, 0xB4::8, 0x00C04FD430C8::48>>
  @ns_oid <<0x6BA7B812::32, 0x9DAD::16, 0x11D1::16, 0x80::8, 0xB4::8, 0x00C04FD430C8::48>>
  @ns_x500 <<0x6BA7B814::32, 0x9DAD::16, 0x11D1::16, 0x80::8, 0xB4::8, 0x00C04FD430C8::48>>

  @doc """
  Returns the standard DNS namespace UUID (RFC 4122 Appendix C).
  """
  def ns_dns, do: @ns_dns

  @doc """
  Returns the standard URL namespace UUID (RFC 4122 Appendix C).
  """
  def ns_url, do: @ns_url

  @doc """
  Returns the standard OID namespace UUID (RFC 4122 Appendix C).
  """
  def ns_oid, do: @ns_oid

  @doc """
  Returns the standard X.500 DN namespace UUID (RFC 4122 Appendix C).
  """
  def ns_x500, do: @ns_x500

  @doc """
  Generates a random UUID v4 (128-bit, RFC 4122 compliant).

  Returns raw 16-byte binary with version 4 and variant 1 bits set.

      iex> uuid = GridCodec.Types.UUID.generate_v4()
      iex> byte_size(uuid)
      16
  """
  @spec generate_v4() :: <<_::128>>
  def generate_v4 do
    <<a::48, _v::4, b::12, _r::2, c::62>> = :crypto.strong_rand_bytes(16)
    <<a::48, 4::4, b::12, 2::2, c::62>>
  end

  @doc """
  Generates a deterministic UUID v5 (SHA-1 name-based, RFC 4122 Section 4.3).

  Given a namespace UUID and a name, always produces the same UUID. Useful for
  deriving stable IDs from known inputs (e.g. user email, DNS name, URL).

  ## Parameters

    * `namespace` — a 16-byte binary UUID, or one of the atoms `:dns`, `:url`,
      `:oid`, `:x500` for the standard RFC 4122 namespaces.
    * `name` — arbitrary binary (string, etc.) to hash within the namespace.

  ## Examples

      iex> ns = GridCodec.Types.UUID.ns_dns()
      iex> a = GridCodec.Types.UUID.generate_v5(ns, "example.com")
      iex> b = GridCodec.Types.UUID.generate_v5(ns, "example.com")
      iex> a == b
      true
      iex> byte_size(a)
      16

      iex> GridCodec.Types.UUID.generate_v5(:dns, "example.com") == GridCodec.Types.UUID.generate_v5(GridCodec.Types.UUID.ns_dns(), "example.com")
      true
  """
  @spec generate_v5(<<_::128>> | :dns | :url | :oid | :x500, binary()) :: <<_::128>>
  def generate_v5(namespace, name) when is_binary(name) do
    ns = resolve_namespace(namespace)
    <<a::48, _v::4, b::12, _r::2, c::62, _rest::binary>> = :crypto.hash(:sha, ns <> name)
    <<a::48, 5::4, b::12, 2::2, c::62>>
  end

  defp resolve_namespace(:dns), do: @ns_dns
  defp resolve_namespace(:url), do: @ns_url
  defp resolve_namespace(:oid), do: @ns_oid
  defp resolve_namespace(:x500), do: @ns_x500
  defp resolve_namespace(<<_::binary-size(16)>> = ns), do: ns

  @doc """
  Generates a UUID v7 (time-sortable, RFC 9562 compliant).

  Uses millisecond Unix timestamp for the first 48 bits, ensuring
  lexicographic ordering by creation time. Ideal for database primary
  keys and distributed systems.

      iex> uuid = GridCodec.Types.UUID.generate_v7()
      iex> byte_size(uuid)
      16
  """
  @spec generate_v7() :: <<_::128>>
  def generate_v7 do
    ms = System.system_time(:millisecond)
    <<rand_a::12, _::6, rand_b::62>> = :crypto.strong_rand_bytes(10)
    <<ms::48, 7::4, rand_a::12, 2::2, rand_b::62>>
  end

  @doc """
  Extracts the millisecond timestamp from a UUID v7.

  Returns `nil` if the UUID is not v7 (version bits != 0b0111).

      iex> uuid = GridCodec.Types.UUID.generate_v7()
      iex> is_integer(GridCodec.Types.UUID.v7_timestamp(uuid))
      true
  """
  @spec v7_timestamp(<<_::128>>) :: integer() | nil
  def v7_timestamp(<<ms::48, 7::4, _::76>>), do: ms
  def v7_timestamp(_), do: nil

  @impl true
  def coerce_ast(var) do
    quote do
      case unquote(var) do
        nil ->
          {:ok, nil}

        <<_::binary-size(16)>> = v ->
          {:ok, v}

        v when is_binary(v) and byte_size(v) == 36 ->
          {:ok, GridCodec.Types.UUIDString.parse_uuid_string!(v)}

        v when is_binary(v) and byte_size(v) == 32 ->
          {:ok, GridCodec.Types.UUIDString.parse_uuid_nodash!(v)}

        v ->
          {:error, "expected UUID binary or string, got #{inspect(v)}"}
      end
    end
  end

  @impl true
  def validate_ast(var, field, mod) do
    quote do
      case unquote(var) do
        nil ->
          :ok

        <<_::binary-size(16)>> ->
          :ok

        v ->
          raise GridCodec.ValidationError.invalid_format(
                  unquote(mod),
                  unquote(field),
                  :uuid,
                  v,
                  "16-byte binary or nil"
                )
      end
    end
  end

  if Code.ensure_loaded?(StreamData) do
    @impl true
    def generator, do: GridCodec.Generators.uuid()
  end
end
