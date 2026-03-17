defmodule GridCodec.Types.CharArray do
  @moduledoc """
  Macro-based fixed-length character array type.

  Char arrays store strings in a fixed-size buffer, padded with null bytes.
  Unlike variable-length strings, char arrays have a predictable size and
  enable O(1) field access.

  ## Usage

  Define a char array module with a fixed length:

      defmodule MyApp.Types.Symbol do
        use GridCodec.Types.CharArray, length: 8
      end

  Then use it in your codec:

      defmodule MyApp.OrderEvent do
        use GridCodec.Struct

        alias MyApp.Types.Symbol

        defcodec do
          field :order_id, :u64
          field :symbol, Symbol
        end
      end

  ## Encoding/Decoding

  Strings are null-padded to the fixed length:

      # "ABC" → <<65, 66, 67, 0, 0, 0, 0, 0>> (8 bytes)

  Decoding strips trailing null bytes:

      # <<65, 66, 67, 0, 0, 0, 0, 0>> → "ABC"

  ## Truncation

  Strings longer than the fixed length are truncated:

      # length: 4
      # "ABCDEFGH" → "ABCD"

  Use `:truncate` option to control this behavior:
  - `:truncate` (default) - silently truncate
  - `:error` - raise on oversized strings

  ## Example

      defmodule MyApp.Types.Code4 do
        use GridCodec.Types.CharArray, length: 4, on_overflow: :error
      end
  """

  @doc """
  Defines a fixed-length char array type module.

  ## Options

  - `:length` - The fixed length in bytes (required)
  - `:on_overflow` - Behavior when string exceeds length
    - `:truncate` (default) - Truncate to fit
    - `:error` - Raise ArgumentError
  - `:schema` - Schema name for `.grid` export placement (optional)

  ## Example

      defmodule MySymbol do
        use GridCodec.Types.CharArray, length: 8
      end
  """
  defmacro __using__(opts) do
    length = Keyword.fetch!(opts, :length)
    on_overflow = Keyword.get(opts, :on_overflow, :truncate)
    schema_name = Keyword.get(opts, :schema)

    unless is_integer(length) and length > 0 do
      raise ArgumentError, ":length must be a positive integer"
    end

    unless on_overflow in [:truncate, :error] do
      raise ArgumentError, ":on_overflow must be :truncate or :error"
    end

    quote do
      unless Module.has_attribute?(__MODULE__, :moduledoc) do
        @moduledoc "GridCodec fixed-length char array (#{unquote(length)} bytes)."
      end

      @behaviour GridCodec.Type

      @char_array_length unquote(length)
      @on_overflow unquote(on_overflow)
      @__schema_name unquote(schema_name)

      @doc false
      def __char_array_meta__ do
        %{length: @char_array_length, schema: @__schema_name}
      end

      @doc """
      Returns the fixed length of this char array.
      """
      @spec length() :: pos_integer()
      def length, do: @char_array_length

      @doc """
      Encodes a string to a fixed-length binary.

      The string is null-padded to the fixed length.
      If the string exceeds the length, behavior depends on `:on_overflow` option.
      """
      @spec encode(String.t() | nil) :: binary()
      def encode(nil), do: <<0::size(@char_array_length * 8)>>

      unquote(
        case on_overflow do
          :truncate ->
            quote do
              def encode(string) when is_binary(string) do
                byte_len = byte_size(string)

                cond do
                  byte_len == @char_array_length ->
                    string

                  byte_len < @char_array_length ->
                    padding_size = @char_array_length - byte_len
                    <<string::binary, 0::size(padding_size * 8)>>

                  true ->
                    binary_part(string, 0, @char_array_length)
                end
              end
            end

          :error ->
            quote do
              def encode(string) when is_binary(string) do
                byte_len = byte_size(string)

                cond do
                  byte_len == @char_array_length ->
                    string

                  byte_len < @char_array_length ->
                    padding_size = @char_array_length - byte_len
                    <<string::binary, 0::size(padding_size * 8)>>

                  true ->
                    raise ArgumentError,
                          "String length #{byte_len} exceeds char array length #{@char_array_length}"
                end
              end
            end
        end
      )

      @doc """
      Decodes a fixed-length binary to a string.

      Trailing null bytes are stripped.
      """
      @spec decode(binary()) :: String.t()
      def decode(binary) when byte_size(binary) >= @char_array_length do
        data = binary_part(binary, 0, @char_array_length)

        case :binary.match(data, <<0>>) do
          {0, _} -> ""
          {pos, _} -> binary_part(data, 0, pos)
          :nomatch -> data
        end
      end

      # GridCodec.Type callbacks

      @impl GridCodec.Type
      def size, do: @char_array_length

      @impl GridCodec.Type
      def alignment, do: 1

      @impl GridCodec.Type
      def null_value, do: String.duplicate(<<0>>, @char_array_length)

      unquote(
        case on_overflow do
          :truncate ->
            quote do
              @impl GridCodec.Type
              def encode_ast(name, _default, _endian, data_var) do
                len = @char_array_length

                quote do
                  case :maps.get(unquote(name), unquote(data_var), nil) do
                    nil ->
                      <<0::size(unquote(len) * 8)>>

                    string when is_binary(string) ->
                      case byte_size(string) do
                        unquote(len) ->
                          string

                        bl when bl < unquote(len) ->
                          <<string::binary, 0::size((unquote(len) - bl) * 8)>>

                        _ ->
                          binary_part(string, 0, unquote(len))
                      end
                  end :: binary - size(unquote(len))
                end
              end
            end

          :error ->
            quote do
              @impl GridCodec.Type
              def encode_ast(name, _default, _endian, data_var) do
                len = @char_array_length

                quote do
                  case :maps.get(unquote(name), unquote(data_var), nil) do
                    nil ->
                      <<0::size(unquote(len) * 8)>>

                    string when is_binary(string) ->
                      case byte_size(string) do
                        unquote(len) ->
                          string

                        bl when bl < unquote(len) ->
                          <<string::binary, 0::size((unquote(len) - bl) * 8)>>

                        _ ->
                          raise ArgumentError,
                                "String length #{byte_size(string)} exceeds char array length #{unquote(len)}"
                      end
                  end :: binary - size(unquote(len))
                end
              end
            end
        end
      )

      @impl GridCodec.Type
      def coerce_ast(var) do
        quote do
          case unquote(var) do
            nil ->
              {:ok, nil}

            v when is_binary(v) ->
              trimmed =
                case :binary.match(v, <<0>>) do
                  {0, _} -> ""
                  {pos, _} -> binary_part(v, 0, pos)
                  :nomatch -> v
                end

              {:ok, trimmed}

            v ->
              {:error, "expected string for char array, got: #{inspect(v)}"}
          end
        end
      end

      unquote(
        case on_overflow do
          :truncate ->
            quote do
              @impl GridCodec.Type
              def validate_ast(var, field, mod) do
                type_module = __MODULE__

                quote do
                  case unquote(var) do
                    nil ->
                      :ok

                    v when is_binary(v) ->
                      :ok

                    v ->
                      raise GridCodec.ValidationError.type_mismatch(
                              unquote(mod),
                              unquote(field),
                              unquote(type_module),
                              v,
                              "binary() or nil"
                            )
                  end
                end
              end
            end

          :error ->
            quote do
              @impl GridCodec.Type
              def validate_ast(var, field, mod) do
                len = @char_array_length
                type_module = __MODULE__

                quote do
                  case unquote(var) do
                    nil ->
                      :ok

                    v when is_binary(v) and byte_size(v) <= unquote(len) ->
                      :ok

                    v when is_binary(v) ->
                      raise GridCodec.ValidationError.out_of_range(
                              unquote(mod),
                              unquote(field),
                              unquote(type_module),
                              byte_size(v),
                              "char array length <= #{unquote(len)} bytes"
                            )

                    v ->
                      raise GridCodec.ValidationError.type_mismatch(
                              unquote(mod),
                              unquote(field),
                              unquote(type_module),
                              v,
                              "binary() or nil"
                            )
                  end
                end
              end
            end
        end
      )

      @impl GridCodec.Type
      def decode_pattern_ast(var, _endian) do
        quote do: unquote(var) :: binary - size(unquote(@char_array_length))
      end

      @impl GridCodec.Type
      def decode_value_ast(var) do
        quote do
          case :binary.match(unquote(var), <<0>>) do
            {0, _} -> ""
            {pos, _} -> binary_part(unquote(var), 0, pos)
            :nomatch -> unquote(var)
          end
        end
      end

      @impl GridCodec.Type
      def getter_ast(offset, _endian, payload_var) do
        len = @char_array_length

        quote do
          <<_::binary-size(unquote(offset)), val::binary-size(unquote(len)), _::binary>> =
            unquote(payload_var)

          case :binary.match(val, <<0>>) do
            {0, _} -> ""
            {pos, _} -> binary_part(val, 0, pos)
            :nomatch -> val
          end
        end
      end

      # Generator for property testing
      if Code.ensure_loaded?(StreamData) do
        @impl GridCodec.Type
        def generator do
          StreamData.bind(
            StreamData.integer(0..@char_array_length),
            fn len ->
              StreamData.map(
                StreamData.binary(length: len),
                fn bin ->
                  # Filter out null bytes to avoid confusion in tests
                  bin
                  |> :binary.bin_to_list()
                  |> Enum.filter(&(&1 != 0))
                  |> :binary.list_to_bin()
                end
              )
            end
          )
        end
      end
    end
  end
end
