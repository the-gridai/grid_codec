defmodule GridCodec.Types.Bitset do
  @moduledoc """
  Macro-based bitset/set type for multiple values from a defined list.

  Bitsets (also known as "set" types) store multiple values from a fixed list
  in a compact integer representation. Each value is a single bit, allowing
  efficient storage and fast set operations.

  Use this when you need to store **multiple values** from a predefined list.
  For **single value** selection, use `GridCodec.Types.Enum` instead.

  ## When to Use

  - **Bitset/Set**: Multiple simultaneous values (e.g., permissions, features, tags)
  - **Enum**: Single value from a list (e.g., status, state, type)

  ## Usage

  Define a bitset module:

      defmodule MyApp.Permissions do
        use GridCodec.Types.Bitset, size: :u8

        flag :read,    0   # bit 0
        flag :write,   1   # bit 1
        flag :execute, 2   # bit 2
        flag :admin,   3   # bit 3
      end

  Then use it in your codec:

      defmodule MyApp.UserEvent do
        use GridCodec.Struct

        alias MyApp.Permissions

        defcodec do
          field :user_id, :uuid
          field :perms, Permissions
        end
      end

  ## Encoding/Decoding

  Bitsets encode to/from MapSets of atoms:

      # Encoding - user has read AND write permissions
      data = %{perms: MapSet.new([:read, :write])}
      {:ok, binary} = MyCodec.encode(data)

      # Decoding
      {:ok, decoded} = MyCodec.decode(binary)
      decoded.perms
      #=> MapSet<[:read, :write]>

  ## Underlying Types

  Bitsets support different sizes:
  - `:u8` - 8 values (1 byte)
  - `:u16` - 16 values (2 bytes)
  - `:u32` - 32 values (4 bytes)
  - `:u64` - 64 values (8 bytes)

  ## Raw Access

  You can also work with raw integer values:

      MyApp.Permissions.to_integer(MapSet.new([:read, :write]))
      #=> 3 (binary: 00000011)

      MyApp.Permissions.from_integer(3)
      #=> MapSet<[:active, :premium]>

  ## Checking Flags

      flags = MapSet.new([:active, :premium])
      MyApp.OrderFlags.active?(flags)     #=> true
      MyApp.OrderFlags.suspended?(flags)  #=> false
  """

  @type size :: :u8 | :u16 | :u32 | :u64

  @doc """
  Defines a bitset type module.

  ## Options

  - `:size` - The underlying integer type (`:u8`, `:u16`, `:u32`, `:u64`)
              Default: `:u8`
  - `:schema` - Schema name for `.grid` export placement (optional)

  ## Example

      defmodule MyFlags do
        use GridCodec.Types.Bitset, size: :u8

        flag :a, 0
        flag :b, 1
      end
  """
  defmacro __using__(opts) do
    size = Keyword.get(opts, :size, :u8)
    schema_name = Keyword.get(opts, :schema)

    {byte_size, max_bits} =
      case size do
        :u8 ->
          {1, 8}

        :u16 ->
          {2, 16}

        :u32 ->
          {4, 32}

        :u64 ->
          {8, 64}

        other ->
          raise ArgumentError,
                "Invalid bitset size: #{inspect(other)}. Use :u8, :u16, :u32, or :u64"
      end

    quote do
      unless Module.has_attribute?(__MODULE__, :moduledoc) do
        @moduledoc "GridCodec bitset type (#{unquote(size)} encoding)."
      end

      @behaviour GridCodec.Type

      import GridCodec.Types.Bitset, only: [flag: 2]

      Module.register_attribute(__MODULE__, :bitset_flags, accumulate: true)
      @before_compile GridCodec.Types.Bitset

      @bitset_size unquote(size)
      @bitset_byte_size unquote(byte_size)
      @bitset_max_bits unquote(max_bits)
      @__schema_name unquote(schema_name)

      # GridCodec.Type callbacks
      @impl GridCodec.Type
      def size, do: @bitset_byte_size

      @impl GridCodec.Type
      def alignment, do: @bitset_byte_size

      @impl GridCodec.Type
      def null_value do
        case @bitset_size do
          :u8 -> 255
          :u16 -> 65535
          :u32 -> 4_294_967_295
          :u64 -> 18_446_744_073_709_551_615
        end
      end
    end
  end

  @doc """
  Defines a flag with a name and bit position.

  ## Example

      flag :active, 0    # bit 0 (value 1)
      flag :premium, 3   # bit 3 (value 8)
  """
  defmacro flag(name, bit_position) when is_atom(name) and is_integer(bit_position) do
    quote do
      if unquote(bit_position) >= @bitset_max_bits do
        raise CompileError,
          description:
            "Bit position #{unquote(bit_position)} exceeds maximum #{@bitset_max_bits - 1} for #{@bitset_size}"
      end

      @bitset_flags {unquote(name), unquote(bit_position)}
    end
  end

  # Helper functions to generate binary specs without triggering type checker warnings
  # These are called with specific size values, avoiding the case-on-constant issue
  @doc false
  def __encode_spec__(:u8, _endian), do: quote(do: unsigned - 8)
  def __encode_spec__(:u16, :little), do: quote(do: unsigned - little - 16)
  def __encode_spec__(:u16, :big), do: quote(do: unsigned - big - 16)
  def __encode_spec__(:u32, :little), do: quote(do: unsigned - little - 32)
  def __encode_spec__(:u32, :big), do: quote(do: unsigned - big - 32)
  def __encode_spec__(:u64, :little), do: quote(do: unsigned - little - 64)
  def __encode_spec__(:u64, :big), do: quote(do: unsigned - big - 64)

  @doc false
  def __decode_spec__(:u8, _endian), do: quote(do: unsigned - 8)
  def __decode_spec__(:u16, :little), do: quote(do: unsigned - little - 16)
  def __decode_spec__(:u16, :big), do: quote(do: unsigned - big - 16)
  def __decode_spec__(:u32, :little), do: quote(do: unsigned - little - 32)
  def __decode_spec__(:u32, :big), do: quote(do: unsigned - big - 32)
  def __decode_spec__(:u64, :little), do: quote(do: unsigned - little - 64)
  def __decode_spec__(:u64, :big), do: quote(do: unsigned - big - 64)

  @doc false
  def __getter_body__(:u8, _endian, offset, payload_var, mod) do
    quote do
      <<_::binary-size(unquote(offset)), val::unsigned-8, _::binary>> =
        unquote(payload_var)

      unquote(mod).from_integer(val)
    end
  end

  def __getter_body__(:u16, :little, offset, payload_var, mod) do
    quote do
      <<_::binary-size(unquote(offset)), val::unsigned-little-16, _::binary>> =
        unquote(payload_var)

      unquote(mod).from_integer(val)
    end
  end

  def __getter_body__(:u16, :big, offset, payload_var, mod) do
    quote do
      <<_::binary-size(unquote(offset)), val::unsigned-big-16, _::binary>> =
        unquote(payload_var)

      unquote(mod).from_integer(val)
    end
  end

  def __getter_body__(:u32, :little, offset, payload_var, mod) do
    quote do
      <<_::binary-size(unquote(offset)), val::unsigned-little-32, _::binary>> =
        unquote(payload_var)

      unquote(mod).from_integer(val)
    end
  end

  def __getter_body__(:u32, :big, offset, payload_var, mod) do
    quote do
      <<_::binary-size(unquote(offset)), val::unsigned-big-32, _::binary>> =
        unquote(payload_var)

      unquote(mod).from_integer(val)
    end
  end

  def __getter_body__(:u64, :little, offset, payload_var, mod) do
    quote do
      <<_::binary-size(unquote(offset)), val::unsigned-little-64, _::binary>> =
        unquote(payload_var)

      unquote(mod).from_integer(val)
    end
  end

  def __getter_body__(:u64, :big, offset, payload_var, mod) do
    quote do
      <<_::binary-size(unquote(offset)), val::unsigned-big-64, _::binary>> =
        unquote(payload_var)

      unquote(mod).from_integer(val)
    end
  end

  defmacro __before_compile__(env) do
    flags = Module.get_attribute(env.module, :bitset_flags) |> Enum.reverse()

    # Check for duplicate bit positions
    positions = Enum.map(flags, fn {_, pos} -> pos end)

    if length(positions) != length(Enum.uniq(positions)) do
      raise CompileError,
        description: "Duplicate bit positions in bitset #{inspect(env.module)}"
    end

    # Check for duplicate names
    names = Enum.map(flags, fn {name, _} -> name end)

    if length(names) != length(Enum.uniq(names)) do
      raise CompileError,
        description: "Duplicate flag names in bitset #{inspect(env.module)}"
    end

    flag_map = Map.new(flags)
    all_flags = names
    string_flag_map = Map.new(flags, fn {name, _bit_pos} -> {Atom.to_string(name), name} end)

    # Generate predicate functions for each flag
    predicates =
      Enum.map(flags, fn {name, bit_pos} ->
        predicate_name = String.to_atom("#{name}?")

        quote do
          @doc """
          Returns true if the `#{unquote(name)}` flag is set.
          """
          def unquote(predicate_name)(flags) when is_struct(flags, MapSet) do
            MapSet.member?(flags, unquote(name))
          end

          def unquote(predicate_name)(integer) when is_integer(integer) do
            Bitwise.band(integer, Bitwise.bsl(1, unquote(bit_pos))) != 0
          end
        end
      end)

    # Compile-time inlined to_integer: MapSet.member? + Bitwise.bor per flag
    ti_acc = Macro.var(:acc, __MODULE__)
    ti_flags = Macro.var(:flags_input, __MODULE__)

    to_integer_checks =
      Enum.map(flags, fn {name, bit_pos} ->
        bit_value = Bitwise.bsl(1, bit_pos)

        quote do
          unquote(ti_acc) =
            if MapSet.member?(unquote(ti_flags), unquote(name)),
              do: Bitwise.bor(unquote(ti_acc), unquote(bit_value)),
              else: unquote(ti_acc)
        end
      end)

    # Compile-time inlined from_integer: Bitwise.band per flag, build list then MapSet
    fi_int = Macro.var(:v, __MODULE__)
    fi_list = Macro.var(:list, __MODULE__)

    from_integer_checks =
      Enum.map(flags, fn {name, bit_pos} ->
        bit_value = Bitwise.bsl(1, bit_pos)

        quote do
          unquote(fi_list) =
            if Bitwise.band(unquote(fi_int), unquote(bit_value)) != 0,
              do: [unquote(name) | unquote(fi_list)],
              else: unquote(fi_list)
        end
      end)

    quote do
      @flag_map unquote(Macro.escape(flag_map))
      @all_flags unquote(all_flags)
      @string_flag_map unquote(Macro.escape(string_flag_map))

      @doc false
      def __coerce_flag__(flag) when is_atom(flag) do
        if Map.has_key?(@flag_map, flag) do
          {:ok, flag}
        else
          {:error, "unknown bitset flag: #{inspect(flag)}"}
        end
      end

      @doc false
      def __coerce_flag__(flag) when is_binary(flag) do
        case Map.fetch(@string_flag_map, flag) do
          {:ok, coerced} -> {:ok, coerced}
          :error -> {:error, "unknown bitset flag: #{inspect(flag)}"}
        end
      end

      @doc false
      def __coerce_flag__(flag) do
        {:error, "expected bitset flag as atom or string, got: #{inspect(flag)}"}
      end

      @doc false
      def __coerce_flags__(flags) do
        Enum.reduce_while(flags, {:ok, MapSet.new()}, fn flag, {:ok, acc} ->
          case __coerce_flag__(flag) do
            {:ok, coerced} -> {:cont, {:ok, MapSet.put(acc, coerced)}}
            {:error, _} = error -> {:halt, error}
          end
        end)
      end

      @doc false
      def __bitset_meta__ do
        %{
          size: @bitset_size,
          flags: Enum.sort_by(@flag_map |> Map.to_list(), &elem(&1, 1)),
          schema: @__schema_name
        }
      end

      @doc """
      Returns all defined flag names.
      """
      @spec flags() :: [atom()]
      def flags, do: @all_flags

      @doc """
      Returns the flag to bit position mapping.
      """
      @spec flag_map() :: %{atom() => non_neg_integer()}
      def flag_map, do: @flag_map

      @doc """
      Converts a MapSet of flag atoms to an integer.

      ## Example

          to_integer(MapSet.new([:active, :premium]))
          #=> 5
      """
      @spec to_integer(MapSet.t(atom())) :: non_neg_integer()
      def to_integer(unquote(ti_flags)) when is_struct(unquote(ti_flags), MapSet) do
        unquote(ti_acc) = 0
        unquote_splicing(to_integer_checks)
        unquote(ti_acc)
      end

      @doc """
      Converts an integer to a MapSet of flag atoms.

      ## Example

          from_integer(5)
          #=> MapSet<[:active, :premium]>
      """
      @spec from_integer(non_neg_integer()) :: MapSet.t(atom())
      def from_integer(unquote(fi_int)) when is_integer(unquote(fi_int)) do
        unquote(fi_list) = []
        unquote_splicing(from_integer_checks)
        MapSet.new(unquote(fi_list))
      end

      @doc """
      Encodes flags to binary.
      """
      def encode(nil), do: encode(MapSet.new())

      def encode(flags) when is_struct(flags, MapSet) do
        integer = to_integer(flags)

        case @bitset_size do
          :u8 -> <<integer::8>>
          :u16 -> <<integer::little-16>>
          :u32 -> <<integer::little-32>>
          :u64 -> <<integer::little-64>>
        end
      end

      @doc """
      Decodes binary to flags.
      """
      def decode(binary) do
        integer =
          case @bitset_size do
            :u8 ->
              <<val::8>> = binary
              val

            :u16 ->
              <<val::little-16>> = binary
              val

            :u32 ->
              <<val::little-32>> = binary
              val

            :u64 ->
              <<val::little-64>> = binary
              val
          end

        from_integer(integer)
      end

      @impl GridCodec.Type
      def encode_ast(name, _default, endian, data_var) do
        encode_spec = unquote(__MODULE__).__encode_spec__(@bitset_size, endian)
        flags_var = Macro.var(:__bs_flags__, __MODULE__)
        acc_var = Macro.var(:__bs_acc__, __MODULE__)

        checks =
          for {flag_name, bit_pos} <- @bitset_flags do
            bit_value = Bitwise.bsl(1, bit_pos)

            quote do
              unquote(acc_var) =
                if MapSet.member?(unquote(flags_var), unquote(flag_name)),
                  do: Bitwise.bor(unquote(acc_var), unquote(bit_value)),
                  else: unquote(acc_var)
            end
          end

        quote do
          case :maps.get(unquote(name), unquote(data_var), nil) do
            nil ->
              0

            unquote(flags_var) ->
              unquote(acc_var) = 0
              unquote_splicing(checks)
              unquote(acc_var)
          end :: unquote(encode_spec)
        end
      end

      @impl GridCodec.Type
      def coerce_ast(var) do
        mod = __MODULE__

        quote do
          case unquote(var) do
            nil ->
              {:ok, nil}

            %MapSet{} = v ->
              unquote(mod).__coerce_flags__(MapSet.to_list(v))

            v when is_list(v) ->
              unquote(mod).__coerce_flags__(v)

            v when is_integer(v) ->
              {:ok, unquote(mod).from_integer(v)}

            v ->
              {:error, "expected MapSet, list, or integer for bitset, got: #{inspect(v)}"}
          end
        end
      end

      @impl GridCodec.Type
      def decode_pattern_ast(var, endian) do
        decode_spec = unquote(__MODULE__).__decode_spec__(@bitset_size, endian)
        quote do: unquote(var) :: unquote(decode_spec)
      end

      @impl GridCodec.Type
      def decode_value_ast(var) do
        mod = __MODULE__

        quote do
          unquote(mod).from_integer(unquote(var))
        end
      end

      @impl GridCodec.Type
      def getter_ast(offset, endian, payload_var) do
        unquote(__MODULE__).__getter_body__(@bitset_size, endian, offset, payload_var, __MODULE__)
      end

      # Predicates
      unquote_splicing(predicates)

      # Generator for property testing
      if Code.ensure_loaded?(StreamData) do
        @impl GridCodec.Type
        def generator do
          StreamData.map(
            StreamData.list_of(StreamData.member_of(@all_flags)),
            &MapSet.new/1
          )
        end
      end
    end
  end
end
