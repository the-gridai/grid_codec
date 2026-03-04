defmodule GridCodec.Types.Bool do
  @moduledoc """
  Boolean type encoded as a single byte.

  Encodes `true` as `1` and `false` as `0`. When decoding, any non-zero
  value is interpreted as `true`.

  ## Examples

      defmodule MyCodec do
        use GridCodec.Struct

        defcodec do
          field :is_active, :bool
          field :is_verified, :bool, default: false
        end
      end

      # Encode (includes 8-byte header by default)
      binary = MyCodec.encode(%MyCodec{is_active: true, is_verified: false})

      # Decode
      {:ok, %MyCodec{is_active: true, is_verified: false}} = MyCodec.decode(binary)

  ## Wire Format

      Offset  Size  Description
      ──────  ────  ───────────
      0       1     0 = false, non-zero = true

  ## Encoding Rules

  - `true` → `0x01`
  - `false` → `0x00`
  - `nil` with default → default value encoded

  ## Decoding Rules

  - `0x00` → `false`
  - Any other value → `true`

  This "non-zero is true" behavior matches C conventions and provides
  robustness against encoding variations.

  ## Packing Multiple Booleans

  If you have many boolean flags, consider using a single `:u8` or `:u32`
  as a bitfield for better space efficiency:

      defcodec do
        # Instead of 8 separate :bool fields (8 bytes)
        # Use a single u8 bitfield (1 byte)
        field :flags, :u8
      end

      # Then use bitwise operations
      is_active = (flags &&& 0x01) != 0
      is_verified = (flags &&& 0x02) != 0
  """

  @behaviour GridCodec.Type

  # 255 represents null/unset boolean
  @null_value 255

  @impl true
  def size, do: 1

  @impl true
  def alignment, do: 1

  @impl true
  def null_value, do: @null_value

  @impl true
  def encode_ast(field_name, default, _endian, data_var) do
    # Use :maps.get/3 BIF directly (faster than Map.get/3)
    # - true → 1
    # - false → 0
    # - nil (explicit) or missing field → null_value
    quote do
      case :maps.get(unquote(field_name), unquote(data_var), unquote(default)) do
        true -> 1
        false -> 0
        _ -> unquote(@null_value)
      end :: 8
    end
  end

  @impl true
  def decode_pattern_ast(var, _endian) do
    # Decode as unsigned-8, conversion happens in decode_value_ast
    quote do: unquote(var) :: 8
  end

  @impl true
  def decode_value_ast(var) do
    # Convert: 0 -> false, 255 -> nil, other -> true
    quote do
      case unquote(var) do
        0 -> false
        255 -> nil
        _ -> true
      end
    end
  end

  @impl true
  def getter_ast(offset, _endian, payload_var) do
    quote do
      <<_::binary-size(unquote(offset)), value::8, _::binary>> = unquote(payload_var)

      case value do
        0 -> false
        unquote(@null_value) -> nil
        _ -> true
      end
    end
  end

  @doc """
  Extracts a bool from a binary at the given offset.
  """
  def get_value(binary, offset, _endian) when is_binary(binary) do
    <<_::binary-size(offset), value::8, _::binary>> = binary

    case value do
      0 -> false
      255 -> nil
      _ -> true
    end
  end

  @impl true
  def coerce_ast(var) do
    quote do
      case unquote(var) do
        nil -> {:ok, nil}
        v when is_boolean(v) -> {:ok, v}
        "true" -> {:ok, true}
        "false" -> {:ok, false}
        1 -> {:ok, true}
        0 -> {:ok, false}
        v -> {:error, "expected boolean, got #{inspect(v)}"}
      end
    end
  end

  @impl true
  def validate_ast(var, field, mod) do
    quote do
      case unquote(var) do
        nil ->
          :ok

        v when is_boolean(v) ->
          :ok

        v ->
          raise GridCodec.ValidationError.type_mismatch(
                  unquote(mod),
                  unquote(field),
                  :bool,
                  v,
                  "true, false, or nil"
                )
      end
    end
  end

  if Code.ensure_loaded?(GridCodec.Generators) do
    @impl true
    def generator, do: GridCodec.Generators.bool()
  end
end
