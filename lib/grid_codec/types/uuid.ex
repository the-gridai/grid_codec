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
      MyCodec.encode(%{id: id, parent_id: <<0::128>>})

      # Zero-copy access returns a sub-binary reference
      env = MyCodec.wrap(binary)
      id = MyCodec.get(env, :id)  # Sub-binary, no copy!

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
  When you call `get(env, :uuid_field)`, you receive a sub-binary reference
  to the original payload—no memory allocation or copy occurs.

  This is ideal for high-throughput scenarios where you need to extract
  IDs for routing or filtering without full message decode.

  ## Generating UUIDs

      # Random (v4) UUID
      :crypto.strong_rand_bytes(16)

      # Using the `uuid` package for proper v4
      UUID.uuid4(:raw)
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

  if Code.ensure_loaded?(GridCodec.Generators) do
    @impl true
    def generator, do: GridCodec.Generators.uuid()
  end
end
