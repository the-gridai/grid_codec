defmodule GridCodec.Types.UUIDString do
  @moduledoc """
  UUID type that decodes to a formatted string.

  Same wire format as `:uuid` (16 raw bytes), but decodes to a human-readable
  string format like `"550e8400-e29b-41d4-a716-446655440000"`.

  ## When to Use

  - `:uuid` - Maximum performance, raw 16-byte binary, not JSON-safe
  - `:uuid_string` - JSON-safe, human-readable, slight decode overhead

  The inline getter builds a formatted string (`format_uuid/1`), not a sub-binary.
  `get(..., copy: true)` is therefore a no-op for this type (no extra copy).

  ## Examples

      defmodule MyCodec do
        use GridCodec.Struct

        defcodec do
          field :id, :uuid_string      # Decodes to "550e8400-..."
          field :raw_id, :uuid          # Decodes to <<85, 14, 132, ...>>
        end
      end

      # Encoding accepts both formats
      MyCodec.encode(%MyCodec{
        id: "550e8400-e29b-41d4-a716-446655440000",  # String input
        raw_id: <<85, 14, 132, 0, ...>>              # Binary input
      })

      # Decoding returns string format
      {:ok, data} = MyCodec.decode(binary)
      data.id      # => "550e8400-e29b-41d4-a716-446655440000"
      data.raw_id  # => <<85, 14, 132, 0, ...>>

  ## Wire Format

  Same as `:uuid` - 16 raw bytes, maximally efficient.

      Offset  Size  Description
      ──────  ────  ───────────
      0       16    Raw UUID bytes (128 bits)

  ## JSON Compatibility

  The main benefit of `:uuid_string` is JSON compatibility:

      {:ok, struct} = MyCodec.decode(binary)
      JSON.encode!(Map.from_struct(struct))  # Works!

  With `:uuid`, you'd get a `JSON.EncodeError` because raw bytes aren't valid UTF-8.
  """

  @behaviour GridCodec.Type

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
    mod = __MODULE__

    # Accept both string format and raw bytes
    quote do
      (
        value = :maps.get(unquote(field_name), unquote(data_var), nil)

        case value do
          nil ->
            unquote(null_uuid)

          <<_::binary-size(16)>> = raw ->
            raw

          str when is_binary(str) and byte_size(str) == 36 ->
            # Parse "550e8400-e29b-41d4-a716-446655440000" format
            unquote(mod).parse_uuid_string!(str)

          str when is_binary(str) and byte_size(str) == 32 ->
            unquote(mod).parse_uuid_nodash!(str)

          other ->
            raise ArgumentError,
                  "Invalid UUID: #{inspect(other)}. Expected 16-byte binary or UUID string."
        end
      ) :: binary - size(16)
    end
  end

  @impl true
  def decode_pattern_ast(var, _endian) do
    quote do: unquote(var) :: binary - size(16)
  end

  @impl true
  def decode_value_ast(var) do
    null = @null_uuid

    # Convert raw bytes to string format, null to nil
    quote do
      if unquote(var) == unquote(null) do
        nil
      else
        unquote(__MODULE__).format_uuid(unquote(var))
      end
    end
  end

  # Getter allocates a new string — do not implement getter_returns_binary?/0.

  @impl true
  def getter_ast(offset, _endian, payload_var) do
    null = @null_uuid

    quote do
      <<_::binary-size(unquote(offset)), value::binary-size(16), _::binary>> =
        unquote(payload_var)

      if value == unquote(null) do
        nil
      else
        unquote(__MODULE__).format_uuid(value)
      end
    end
  end

  @doc """
  Extracts a UUID from a binary at the given offset, returning as string.
  """
  def get_value(binary, offset, _endian) when is_binary(binary) do
    <<_::binary-size(^offset), value::binary-size(16), _::binary>> = binary
    if value == @null_uuid, do: nil, else: format_uuid(value)
  end

  @doc """
  Formats a 16-byte binary UUID as a string.

  ## Example

      iex> GridCodec.Types.UUIDString.format_uuid(<<85, 14, 132, 0, 226, 155, 65, 212, 167, 22, 68, 102, 85, 68, 0, 0>>)
      "550e8400-e29b-41d4-a716-446655440000"
  """
  @spec format_uuid(binary()) :: String.t()
  def format_uuid(
        <<a1::4, a2::4, a3::4, a4::4, a5::4, a6::4, a7::4, a8::4, b1::4, b2::4, b3::4, b4::4,
          c1::4, c2::4, c3::4, c4::4, d1::4, d2::4, d3::4, d4::4, e1::4, e2::4, e3::4, e4::4,
          e5::4, e6::4, e7::4, e8::4, e9::4, e10::4, e11::4, e12::4>>
      ) do
    <<hex(a1), hex(a2), hex(a3), hex(a4), hex(a5), hex(a6), hex(a7), hex(a8), ?-, hex(b1),
      hex(b2), hex(b3), hex(b4), ?-, hex(c1), hex(c2), hex(c3), hex(c4), ?-, hex(d1), hex(d2),
      hex(d3), hex(d4), ?-, hex(e1), hex(e2), hex(e3), hex(e4), hex(e5), hex(e6), hex(e7),
      hex(e8), hex(e9), hex(e10), hex(e11), hex(e12)>>
  end

  @compile {:inline, hex: 1, format_uuid: 1}
  defp hex(n) when n < 10, do: n + ?0
  defp hex(n), do: n + ?a - 10

  @doc """
  Parses a UUID string into a 16-byte binary.

  ## Example

      iex> GridCodec.Types.UUIDString.parse_uuid_string!("550e8400-e29b-41d4-a716-446655440000")
      <<85, 14, 132, 0, 226, 155, 65, 212, 167, 22, 68, 102, 85, 68, 0, 0>>
  """
  @spec parse_uuid_string!(String.t()) :: binary()
  def parse_uuid_string!(<<
        a1,
        a2,
        a3,
        a4,
        a5,
        a6,
        a7,
        a8,
        ?-,
        b1,
        b2,
        b3,
        b4,
        ?-,
        c1,
        c2,
        c3,
        c4,
        ?-,
        d1,
        d2,
        d3,
        d4,
        ?-,
        e1,
        e2,
        e3,
        e4,
        e5,
        e6,
        e7,
        e8,
        e9,
        e10,
        e11,
        e12
      >>) do
    <<unhex(a1)::4, unhex(a2)::4, unhex(a3)::4, unhex(a4)::4, unhex(a5)::4, unhex(a6)::4,
      unhex(a7)::4, unhex(a8)::4, unhex(b1)::4, unhex(b2)::4, unhex(b3)::4, unhex(b4)::4,
      unhex(c1)::4, unhex(c2)::4, unhex(c3)::4, unhex(c4)::4, unhex(d1)::4, unhex(d2)::4,
      unhex(d3)::4, unhex(d4)::4, unhex(e1)::4, unhex(e2)::4, unhex(e3)::4, unhex(e4)::4,
      unhex(e5)::4, unhex(e6)::4, unhex(e7)::4, unhex(e8)::4, unhex(e9)::4, unhex(e10)::4,
      unhex(e11)::4, unhex(e12)::4>>
  end

  @doc """
  Parses a 32-char hex UUID (no dashes) into a 16-byte binary.

  Uses direct byte extraction and arithmetic instead of `Base.decode16!/2`
  to avoid sub-binary allocation and generic parsing overhead.

  ## Example

      iex> GridCodec.Types.UUIDString.parse_uuid_nodash!("550e8400e29b41d4a716446655440000")
      <<85, 14, 132, 0, 226, 155, 65, 212, 167, 22, 68, 102, 85, 68, 0, 0>>
  """
  @spec parse_uuid_nodash!(String.t()) :: binary()
  def parse_uuid_nodash!(<<
        a1,
        a2,
        a3,
        a4,
        a5,
        a6,
        a7,
        a8,
        b1,
        b2,
        b3,
        b4,
        c1,
        c2,
        c3,
        c4,
        d1,
        d2,
        d3,
        d4,
        e1,
        e2,
        e3,
        e4,
        e5,
        e6,
        e7,
        e8,
        e9,
        e10,
        e11,
        e12
      >>) do
    <<unhex(a1)::4, unhex(a2)::4, unhex(a3)::4, unhex(a4)::4, unhex(a5)::4, unhex(a6)::4,
      unhex(a7)::4, unhex(a8)::4, unhex(b1)::4, unhex(b2)::4, unhex(b3)::4, unhex(b4)::4,
      unhex(c1)::4, unhex(c2)::4, unhex(c3)::4, unhex(c4)::4, unhex(d1)::4, unhex(d2)::4,
      unhex(d3)::4, unhex(d4)::4, unhex(e1)::4, unhex(e2)::4, unhex(e3)::4, unhex(e4)::4,
      unhex(e5)::4, unhex(e6)::4, unhex(e7)::4, unhex(e8)::4, unhex(e9)::4, unhex(e10)::4,
      unhex(e11)::4, unhex(e12)::4>>
  end

  @compile {:inline, unhex: 1, parse_uuid_string!: 1, parse_uuid_nodash!: 1}
  defp unhex(c) when c >= ?0 and c <= ?9, do: c - ?0
  defp unhex(c) when c >= ?a and c <= ?f, do: c - ?a + 10
  defp unhex(c) when c >= ?A and c <= ?F, do: c - ?A + 10

  @impl true
  def coerce_ast(var) do
    quote do
      case unquote(var) do
        nil ->
          {:ok, nil}

        <<_::binary-size(16)>> = raw ->
          {:ok, GridCodec.Types.UUIDString.format_uuid(raw)}

        v when is_binary(v) and byte_size(v) == 36 ->
          {:ok, v}

        v when is_binary(v) and byte_size(v) == 32 ->
          try do
            {:ok,
             GridCodec.Types.UUIDString.format_uuid(
               GridCodec.Types.UUIDString.parse_uuid_nodash!(v)
             )}
          rescue
            _ -> {:error, "invalid UUID format: #{inspect(v)}"}
          end

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

        s when is_binary(s) and byte_size(s) == 36 ->
          :ok

        s when is_binary(s) and byte_size(s) == 32 ->
          :ok

        v ->
          raise GridCodec.ValidationError.invalid_format(
                  unquote(mod),
                  unquote(field),
                  :uuid_string,
                  v,
                  "16-byte binary, 36-char UUID string, 32-char hex string, or nil"
                )
      end
    end
  end

  if Code.ensure_loaded?(StreamData) do
    @impl true
    def generator do
      # Generate as formatted string
      StreamData.map(GridCodec.Generators.uuid(), &format_uuid/1)
    end
  end
end
