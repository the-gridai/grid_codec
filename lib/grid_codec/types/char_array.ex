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
        use GridCodec, types: [symbol: MyApp.Types.Symbol]

        defcodec do
          field :order_id, :u64
          field :symbol, :symbol
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

  ## Example

      defmodule MySymbol do
        use GridCodec.Types.CharArray, length: 8
      end
  """
  defmacro __using__(opts) do
    length = Keyword.fetch!(opts, :length)
    on_overflow = Keyword.get(opts, :on_overflow, :truncate)

    unless is_integer(length) and length > 0 do
      raise ArgumentError, ":length must be a positive integer"
    end

    unless on_overflow in [:truncate, :error] do
      raise ArgumentError, ":on_overflow must be :truncate or :error"
    end

    quote do
      @behaviour GridCodec.Type

      @char_array_length unquote(length)
      @on_overflow unquote(on_overflow)

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

      def encode(string) when is_binary(string) do
        byte_len = byte_size(string)

        cond do
          byte_len == @char_array_length ->
            string

          byte_len < @char_array_length ->
            padding_size = @char_array_length - byte_len
            <<string::binary, 0::size(padding_size * 8)>>

          @on_overflow == :truncate ->
            binary_part(string, 0, @char_array_length)

          @on_overflow == :error ->
            raise ArgumentError,
                  "String length #{byte_len} exceeds char array length #{@char_array_length}"
        end
      end

      @doc """
      Decodes a fixed-length binary to a string.

      Trailing null bytes are stripped.
      """
      @spec decode(binary()) :: String.t()
      def decode(binary) when byte_size(binary) == @char_array_length do
        binary
        |> :binary.bin_to_list()
        |> Enum.take_while(&(&1 != 0))
        |> :binary.list_to_bin()
      end

      def decode(binary) when byte_size(binary) > @char_array_length do
        binary
        |> binary_part(0, @char_array_length)
        |> decode()
      end

      # GridCodec.Type callbacks

      @impl GridCodec.Type
      def size, do: @char_array_length

      @impl GridCodec.Type
      def alignment, do: 1

      @impl GridCodec.Type
      def null_value, do: String.duplicate(<<0>>, @char_array_length)

      @impl GridCodec.Type
      def encode_ast(name, _default, _endian, data_var) do
        quote do
          (fn ->
             val = Map.get(unquote(data_var), unquote(name))
             unquote(__MODULE__).encode(val)
           end).() :: binary - size(unquote(@char_array_length))
        end
      end

      @impl GridCodec.Type
      def decode_pattern_ast(var, _endian) do
        quote do
          unquote(var) :: binary - size(unquote(@char_array_length))
        end
      end

      @impl GridCodec.Type
      def decode_value_ast(var) do
        quote do
          unquote(__MODULE__).decode(unquote(var))
        end
      end

      @impl GridCodec.Type
      def getter_ast(offset, _endian, payload_var) do
        quote do
          <<_::binary-size(unquote(offset)), val::binary-size(unquote(@char_array_length)),
            _::binary>> = unquote(payload_var)

          unquote(__MODULE__).decode(val)
        end
      end

      # Generator for property testing
      if Code.ensure_loaded?(GridCodec.Generators) do
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
