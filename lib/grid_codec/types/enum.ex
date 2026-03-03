defmodule GridCodec.Types.Enum do
  @moduledoc """
  Enumeration type for fixed-width integer values with named variants.

  Enums provide:
  - Fixed-size encoding (u8, u16, or u32)
  - Named variants with integer values
  - Unknown values preserved (forward compatibility)
  - Null sentinel value support

  ## Defining Enums

  Enums are defined using the `defenum` macro in your codec:

      defmodule OrderSide do
        use GridCodec.Types.Enum, encoding: :u8

        defenum do
          value :buy, 0
          value :sell, 1
        end
      end

  Or use the shorthand with automatic numbering:

      defmodule OrderStatus do
        use GridCodec.Types.Enum, encoding: :u8

        defenum do
          value :pending      # 0
          value :filled       # 1
          value :cancelled    # 2
          value :rejected     # 3
        end
      end

  ## Using in Codecs

      defmodule OrderEvent do
        use GridCodec.Struct

        alias MyApp.Types.OrderSide
        alias MyApp.Types.OrderStatus

        defcodec do
          field :id, :u64
          field :side, OrderSide
          field :status, OrderStatus
        end
      end

  ## Wire Format

  Enums are encoded as their underlying integer type:

  | Encoding | Size | Range |
  |----------|------|-------|
  | `:u8` | 1 byte | 0-254 (255 = null) |
  | `:u16` | 2 bytes | 0-65534 (65535 = null) |
  | `:u32` | 4 bytes | 0-4294967294 (max = null) |

  ## Unknown Values

  When decoding unknown values, GridCodec returns the raw integer:

      # If wire contains value 5 but only 0-2 are defined
      {:ok, %{status: 5}} = OrderEvent.decode(binary)

  This enables forward compatibility when new enum values are added.

  ## Null Values

  Use the null sentinel to represent "not set":

      OrderSide.encode(nil)   # => <<255>> for u8
      OrderSide.decode(<<255>>) # => nil
  """

  @doc """
  Behavior callbacks for enum types.
  """
  @type known_value() :: atom()
  @type value() :: known_value() | non_neg_integer() | nil
  @type encoded() :: binary()

  @callback values() :: [{atom(), non_neg_integer()}]
  @callback encoding() :: :u8 | :u16 | :u32
  @callback encode(value()) :: encoded()
  @callback decode(encoded()) :: {value(), binary()}
  @callback to_integer(known_value()) :: non_neg_integer()
  @callback to_atom(non_neg_integer()) :: known_value() | non_neg_integer()

  @doc false
  defmacro __using__(opts) do
    encoding = Keyword.get(opts, :encoding, :u8)

    quote do
      @behaviour GridCodec.Type
      @behaviour GridCodec.Types.Enum

      import GridCodec.Types.Enum, only: [defenum: 1, value: 1, value: 2]

      Module.register_attribute(__MODULE__, :enum_values, accumulate: true)
      Module.register_attribute(__MODULE__, :enum_encoding, [])
      Module.put_attribute(__MODULE__, :enum_encoding, unquote(encoding))
      Module.put_attribute(__MODULE__, :enum_next_value, 0)
    end
  end

  @doc """
  Defines the enum values.

  ## Example

      defenum do
        value :pending, 0
        value :active, 1
        value :closed, 2
      end
  """
  defmacro defenum(do: block) do
    quote do
      unquote(block)
      @before_compile GridCodec.Types.Enum
    end
  end

  @doc """
  Defines an enum value with explicit integer.
  """
  defmacro value(name, int) when is_atom(name) and is_integer(int) do
    quote do
      @enum_values {unquote(name), unquote(int)}
      Module.put_attribute(__MODULE__, :enum_next_value, unquote(int) + 1)
    end
  end

  @doc """
  Defines an enum value with auto-incremented integer.
  """
  defmacro value(name) when is_atom(name) do
    quote do
      next = Module.get_attribute(__MODULE__, :enum_next_value)
      @enum_values {unquote(name), next}
      Module.put_attribute(__MODULE__, :enum_next_value, next + 1)
    end
  end

  @doc false
  defmacro __before_compile__(env) do
    values = Module.get_attribute(env.module, :enum_values) |> Enum.reverse()
    encoding = Module.get_attribute(env.module, :enum_encoding)

    {size, null_value, encode_spec, decode_spec} = encoding_specs(encoding)
    known_type_ast = known_union_ast(values)
    encoded_type_ast = quote(do: <<_::unquote(size * 8)>>)
    known_names = Enum.map(values, fn {name, _} -> name end)
    known_names_doc = known_names |> Enum.map(&inspect/1) |> Enum.join(", ")

    value_doc = """
    Decoded enum value.

    Returns one of:
    - known enum atom (`known()`)
    - unknown raw integer (forward-compatible values)
    - `nil` for the enum null sentinel
    """

    encoded_doc =
      "Fixed-width binary representation for this enum encoding. " <>
        "Encoding: `#{encoding}` (#{size} byte(s), null sentinel #{null_value})."

    encode_spec_little = encode_segment_spec(size, :little)
    encode_spec_big = encode_segment_spec(size, :big)
    get_raw_little_ast = get_raw_value_ast(size, :little)
    get_raw_big_ast = get_raw_value_ast(size, :big)

    # Build lookup maps
    to_int_map = Map.new(values)
    to_atom_map = Map.new(values, fn {k, v} -> {v, k} end)

    quote do
      @typedoc "Known enum atoms declared in `defenum`: #{unquote(known_names_doc)}."
      @type known() :: unquote(known_type_ast)

      @typedoc unquote(value_doc)
      @type t() :: known() | non_neg_integer() | nil

      @typedoc unquote(encoded_doc)
      @type encoded() :: unquote(encoded_type_ast)

      @impl GridCodec.Types.Enum
      def values, do: unquote(Macro.escape(values))

      @impl GridCodec.Types.Enum
      def encoding, do: unquote(encoding)

      @impl GridCodec.Type
      def size, do: unquote(size)

      @impl GridCodec.Type
      def alignment, do: unquote(size)

      @impl GridCodec.Type
      def null_value, do: unquote(null_value)

      @impl GridCodec.Types.Enum
      @spec to_integer(known()) :: non_neg_integer()
      def to_integer(name) when is_atom(name) do
        case unquote(Macro.escape(to_int_map)) do
          %{^name => int} -> int
          _ -> raise ArgumentError, "Unknown enum value: #{inspect(name)}"
        end
      end

      @impl GridCodec.Types.Enum
      @spec to_atom(non_neg_integer()) :: known() | non_neg_integer()
      def to_atom(int) when is_integer(int) do
        case unquote(Macro.escape(to_atom_map)) do
          %{^int => name} -> name
          # Unknown value - return raw integer
          _ -> int
        end
      end

      @impl GridCodec.Types.Enum
      @spec encode(t()) :: encoded()
      def encode(nil), do: <<unquote(null_value)::unquote(encode_spec)>>

      def encode(name) when is_atom(name) do
        int = to_integer(name)
        <<int::unquote(encode_spec)>>
      end

      def encode(int) when is_integer(int) do
        <<int::unquote(encode_spec)>>
      end

      @impl GridCodec.Types.Enum
      @spec decode(encoded()) :: {t(), binary()}
      def decode(<<unquote(null_value)::unquote(decode_spec), rest::binary>>) do
        {nil, rest}
      end

      def decode(<<int::unquote(decode_spec), rest::binary>>) do
        {to_atom(int), rest}
      end

      # GridCodec.Type callbacks for AST generation
      @impl GridCodec.Type
      def encode_ast(field_name, default, endian, data_var) do
        mod = __MODULE__
        null_val = unquote(null_value)

        encode_spec =
          case endian do
            :little -> unquote(Macro.escape(encode_spec_little))
            :big -> unquote(Macro.escape(encode_spec_big))
          end

        quote do
          case :maps.get(unquote(field_name), unquote(data_var), unquote(default)) do
            nil -> unquote(null_val)
            v when is_atom(v) -> unquote(mod).to_integer(v)
            v when is_integer(v) -> v
          end :: unquote(encode_spec)
        end
      end

      @impl GridCodec.Type
      def decode_pattern_ast(var, _endian) do
        sz = unquote(size)
        # Return the raw bytes, we'll convert in decode_value_ast
        quote do: unquote(var) :: binary - size(unquote(sz))
      end

      @impl GridCodec.Type
      def decode_value_ast(var) do
        mod = __MODULE__

        quote do
          {value, ""} = unquote(mod).decode(unquote(var))
          value
        end
      end

      @impl GridCodec.Type
      def getter_ast(offset, _endian, payload_var) do
        mod = __MODULE__
        sz = unquote(size)

        quote do
          <<_::binary-size(unquote(offset)), raw::binary-size(unquote(sz)), _::binary>> =
            unquote(payload_var)

          {value, ""} = unquote(mod).decode(raw)
          value
        end
      end

      @impl GridCodec.Type
      def compare_values(left, right) do
        left_int = compare_to_integer(left)
        right_int = compare_to_integer(right)

        cond do
          left_int == right_int -> :eq
          left_int < right_int -> :lt
          true -> :gt
        end
      end

      @doc false
      def get_value(binary, offset, endian) when is_binary(binary) do
        raw =
          case endian do
            :little -> unquote(get_raw_little_ast)
            :big -> unquote(get_raw_big_ast)
          end

        case raw do
          unquote(null_value) -> nil
          v -> to_atom(v)
        end
      end

      defp compare_to_integer(nil), do: unquote(null_value)
      defp compare_to_integer(v) when is_atom(v), do: to_integer(v)
      defp compare_to_integer(v) when is_integer(v), do: v

      if Code.ensure_loaded?(GridCodec.Generators) do
        @impl GridCodec.Type
        def generator do
          atoms = unquote(Macro.escape(Enum.map(values, fn {k, _v} -> k end)))
          StreamData.member_of(atoms)
        end
      end
    end
  end

  # Helper to get encoding specifications
  defp encoding_specs(:u8) do
    {1, 255, quote(do: little - unsigned - 8), quote(do: little - unsigned - 8)}
  end

  defp encoding_specs(:u16) do
    {2, 65_535, quote(do: little - unsigned - 16), quote(do: little - unsigned - 16)}
  end

  defp encoding_specs(:u32) do
    {4, 4_294_967_295, quote(do: little - unsigned - 32), quote(do: little - unsigned - 32)}
  end

  defp known_union_ast(values) do
    values
    |> Enum.map(fn {name, _} -> name end)
    |> case do
      [] ->
        quote(do: atom())

      [single] ->
        single

      [first | rest] ->
        Enum.reduce(rest, first, fn atom, acc ->
          quote(do: unquote(acc) | unquote(atom))
        end)
    end
  end

  defp encode_segment_spec(1, :little), do: quote(do: unsigned - 8)
  defp encode_segment_spec(1, :big), do: quote(do: unsigned - 8)
  defp encode_segment_spec(2, :little), do: quote(do: unsigned - little - 16)
  defp encode_segment_spec(2, :big), do: quote(do: unsigned - big - 16)
  defp encode_segment_spec(4, :little), do: quote(do: unsigned - little - 32)
  defp encode_segment_spec(4, :big), do: quote(do: unsigned - big - 32)

  defp get_raw_value_ast(1, :little) do
    quote do
      <<_::binary-size(offset), value::unsigned-8, _::binary>> = binary
      value
    end
  end

  defp get_raw_value_ast(1, :big), do: get_raw_value_ast(1, :little)

  defp get_raw_value_ast(2, :little) do
    quote do
      <<_::binary-size(offset), value::unsigned-little-16, _::binary>> = binary
      value
    end
  end

  defp get_raw_value_ast(2, :big) do
    quote do
      <<_::binary-size(offset), value::unsigned-big-16, _::binary>> = binary
      value
    end
  end

  defp get_raw_value_ast(4, :little) do
    quote do
      <<_::binary-size(offset), value::unsigned-little-32, _::binary>> = binary
      value
    end
  end

  defp get_raw_value_ast(4, :big) do
    quote do
      <<_::binary-size(offset), value::unsigned-big-32, _::binary>> = binary
      value
    end
  end
end
