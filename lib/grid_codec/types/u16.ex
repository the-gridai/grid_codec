defmodule GridCodec.Types.U16 do
  @moduledoc """
  Unsigned 16-bit integer type.

  Encodes values from 0 to 65,535 in two bytes.

  ## Examples

      defmodule MyCodec do
        use GridCodec.Struct

        defcodec do
          field :port, :u16
          field :count, :u16, default: 0
        end
      end

      MyCodec.encode(%{port: 8080, count: 1000})
      # => <<144, 31, 232, 3>> (little-endian)

  ## Wire Format

      Offset  Size  Description
      ──────  ────  ───────────
      0       2     Unsigned 16-bit value (0-65,535)

  ## Byte Order

  With `:little` endian (default): least significant byte first.
  With `:big` endian: most significant byte first.

      # Value: 0x1234 (4660)
      Little-endian: <<0x34, 0x12>>
      Big-endian:    <<0x12, 0x34>>
  """

  @behaviour GridCodec.Type

  @impl true
  def size, do: 2

  @impl true
  def alignment, do: 2

  @impl true
  def null_value, do: 65535

  @null_val 65_535

  @impl true
  def encode_ast(field_name, default, endian, data_var) do
    null_val = @null_val

    case endian do
      :little ->
        quote do
          case :maps.get(unquote(field_name), unquote(data_var), unquote(default)) do
            nil ->
              unquote(null_val)

            v ->
              unquote(GridCodec.Types.Integer.validate_unsigned_ast(quote(do: v), 16, field_name))
          end :: unsigned - little - 16
        end

      :big ->
        quote do
          case :maps.get(unquote(field_name), unquote(data_var), unquote(default)) do
            nil ->
              unquote(null_val)

            v ->
              unquote(GridCodec.Types.Integer.validate_unsigned_ast(quote(do: v), 16, field_name))
          end :: unsigned - big - 16
        end
    end
  end

  @impl true
  def decode_pattern_ast(var, endian) do
    case endian do
      :little -> quote do: unquote(var) :: unsigned - little - 16
      :big -> quote do: unquote(var) :: unsigned - big - 16
    end
  end

  @impl true
  def decode_value_ast(var) do
    null_val = @null_val

    quote do
      case unquote(var) do
        unquote(null_val) -> nil
        v -> v
      end
    end
  end

  @impl true
  def getter_ast(offset, endian, payload_var) do
    null_val = @null_val

    case endian do
      :little ->
        quote do
          <<_::binary-size(unquote(offset)), value::unsigned-little-16, _::binary>> =
            unquote(payload_var)

          case value do
            unquote(null_val) -> nil
            v -> v
          end
        end

      :big ->
        quote do
          <<_::binary-size(unquote(offset)), value::unsigned-big-16, _::binary>> =
            unquote(payload_var)

          case value do
            unquote(null_val) -> nil
            v -> v
          end
        end
    end
  end

  @doc """
  Extracts a u16 value from a binary at the given offset.
  """
  def get_value(binary, offset, endian) when is_binary(binary) do
    case endian do
      :little ->
        <<_::binary-size(offset), value::unsigned-little-16, _::binary>> = binary
        if value == @null_val, do: nil, else: value

      :big ->
        <<_::binary-size(offset), value::unsigned-big-16, _::binary>> = binary
        if value == @null_val, do: nil, else: value
    end
  end

  @impl true
  def coerce_ast(var) do
    quote do
      case unquote(var) do
        nil ->
          {:ok, nil}

        v when is_integer(v) ->
          {:ok, v}

        v when is_binary(v) ->
          case Integer.parse(v) do
            {int, ""} -> {:ok, int}
            _ -> {:error, "cannot parse integer from #{inspect(v)}"}
          end

        v ->
          {:error, "expected integer or string, got #{inspect(v)}"}
      end
    end
  end

  @impl true
  def validate_ast(var, field, mod) do
    GridCodec.Types.Integer.gen_unsigned_validate_ast(var, field, mod, 16, :u16)
  end

  if Code.ensure_loaded?(StreamData) do
    @impl true
    def generator, do: GridCodec.Generators.u16()
  end
end
