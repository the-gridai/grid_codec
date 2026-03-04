defmodule GridCodec.Types.UUIDString do
  @moduledoc """
  UUID type that decodes to a formatted string.

  Same wire format as `:uuid` (16 raw bytes), but decodes to a human-readable
  string format like `"550e8400-e29b-41d4-a716-446655440000"`.

  ## When to Use

  - `:uuid` - Maximum performance, raw 16-byte binary, not JSON-safe
  - `:uuid_string` - JSON-safe, human-readable, slight decode overhead

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
      Jason.encode!(Map.from_struct(struct))  # Works!

  With `:uuid`, you'd get a Jason.EncodeError because raw bytes aren't valid UTF-8.
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
            # Parse "550e8400e29b41d4a716446655440000" format (no dashes)
            Base.decode16!(str, case: :mixed)

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
    <<_::binary-size(offset), value::binary-size(16), _::binary>> = binary
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
        <<a::binary-size(4), b::binary-size(2), c::binary-size(2), d::binary-size(2),
          e::binary-size(6)>>
      ) do
    Base.encode16(a, case: :lower) <>
      "-" <>
      Base.encode16(b, case: :lower) <>
      "-" <>
      Base.encode16(c, case: :lower) <>
      "-" <>
      Base.encode16(d, case: :lower) <>
      "-" <>
      Base.encode16(e, case: :lower)
  end

  @doc """
  Parses a UUID string into a 16-byte binary.

  ## Example

      iex> GridCodec.Types.UUIDString.parse_uuid_string!("550e8400-e29b-41d4-a716-446655440000")
      <<85, 14, 132, 0, 226, 155, 65, 212, 167, 22, 68, 102, 85, 68, 0, 0>>
  """
  @spec parse_uuid_string!(String.t()) :: binary()
  def parse_uuid_string!(uuid_string) when byte_size(uuid_string) == 36 do
    uuid_string
    |> String.replace("-", "")
    |> Base.decode16!(case: :mixed)
  end

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
          {:ok, Base.decode16!(v, case: :mixed)}

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

  if Code.ensure_loaded?(GridCodec.Generators) do
    @impl true
    def generator do
      # Generate as formatted string
      StreamData.map(GridCodec.Generators.uuid(), &format_uuid/1)
    end
  end
end
