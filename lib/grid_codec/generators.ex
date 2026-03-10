if Code.ensure_loaded?(StreamData) do
  defmodule GridCodec.Generators do
    @moduledoc """
    StreamData generators for GridCodec types.

    This module provides generators for property-based testing of codecs.
    It is only compiled when StreamData is available (dev/test environments).

    ## Usage

        # Get generator for a specific type
        gen = GridCodec.Generators.for_type(:u64)
        Enum.take(StreamData.list_of(gen), 3)
        # => [[123, 456, 789], [0, 18446744073709551615], ...]

        # Generate a random value map for a codec
        gen = GridCodec.Generators.for_codec(MyCodec)
        [sample] = Enum.take(gen, 1)
        # => %{id: 123, name: "abc", ...}

    ## Generating Random Codecs

    For testing the codec framework itself:

        # Generate a random schema
        schema_gen = GridCodec.Generators.schema()
        [schema] = Enum.take(schema_gen, 1)
        # => [{:id, :u64, []}, {:flag, :bool, []}, ...]

    """

    import StreamData

    @type_generators %{
      u8: &__MODULE__.u8/0,
      u16: &__MODULE__.u16/0,
      u32: &__MODULE__.u32/0,
      u64: &__MODULE__.u64/0,
      i8: &__MODULE__.i8/0,
      i16: &__MODULE__.i16/0,
      i32: &__MODULE__.i32/0,
      i64: &__MODULE__.i64/0,
      f32: &__MODULE__.f32/0,
      f64: &__MODULE__.f64/0,
      uuid: &__MODULE__.uuid/0,
      bool: &__MODULE__.bool/0,
      string: &__MODULE__.string/0,
      string8: &__MODULE__.string8/0,
      string16: &__MODULE__.default_string16/0,
      string32: &__MODULE__.default_string32/0,
      timestamp_us: &__MODULE__.timestamp_us/0,
      timestamp_ns: &__MODULE__.timestamp_ns/0,
      datetime_us: &__MODULE__.datetime_us/0,
      datetime_ns: &__MODULE__.datetime_ns/0,
      decimal: &__MODULE__.decimal/0,
      positive_decimal: &__MODULE__.positive_decimal/0,
      uuid_string: &__MODULE__.uuid_string/0
    }

    # ============================================================================
    # Type Generators
    # ============================================================================

    # Note: Max/min values are reserved as null sentinels and excluded from generation

    @doc "Generator for unsigned 8-bit integers (0..254, 255 is null)"
    @spec u8() :: StreamData.t(non_neg_integer())
    def u8, do: integer(0..254)

    @doc "Generator for unsigned 16-bit integers (0..65534, 65535 is null)"
    @spec u16() :: StreamData.t(non_neg_integer())
    def u16, do: integer(0..65_534)

    @doc "Generator for unsigned 32-bit integers (max-1, max is null)"
    @spec u32() :: StreamData.t(non_neg_integer())
    def u32, do: integer(0..4_294_967_294)

    @doc "Generator for unsigned 64-bit integers (max-1, max is null)"
    @spec u64() :: StreamData.t(non_neg_integer())
    def u64 do
      # StreamData.integer/1 supports big integers
      integer(0..18_446_744_073_709_551_614)
    end

    @doc "Generator for signed 8-bit integers (-127..127, -128 is null)"
    @spec i8() :: StreamData.t(integer())
    def i8, do: integer(-127..127)

    @doc "Generator for signed 16-bit integers (-32767..32767, min is null)"
    @spec i16() :: StreamData.t(integer())
    def i16, do: integer(-32_767..32_767)

    @doc "Generator for signed 32-bit integers (min+1..max, min is null)"
    @spec i32() :: StreamData.t(integer())
    def i32, do: integer(-2_147_483_647..2_147_483_647)

    @doc "Generator for signed 64-bit integers (min+1..max, min is null)"
    @spec i64() :: StreamData.t(integer())
    def i64 do
      integer(-9_223_372_036_854_775_807..9_223_372_036_854_775_807)
    end

    @doc "Generator for 32-bit floats (single precision)"
    @spec f32() :: StreamData.t(float())
    def f32 do
      # Generate floats within f32 range, avoiding infinities and NaN
      bind(integer(-1_000_000..1_000_000), fn int ->
        bind(integer(0..999_999), fn frac ->
          constant(int + frac / 1_000_000)
        end)
      end)
    end

    @doc "Generator for 64-bit floats (double precision)"
    @spec f64() :: StreamData.t(float())
    def f64 do
      # Similar to f32 but with more range
      bind(integer(-1_000_000_000..1_000_000_000), fn int ->
        bind(integer(0..999_999_999), fn frac ->
          constant(int + frac / 1_000_000_000)
        end)
      end)
    end

    @doc "Generator for 16-byte UUIDs"
    @spec uuid() :: StreamData.t(binary())
    def uuid do
      map(
        list_of(integer(0..255), length: 16),
        fn bytes -> :binary.list_to_bin(bytes) end
      )
    end

    @doc """
    Generator for nullable booleans (true/false/nil).

    Includes nil because GridCodec bool fields are optional by default,
    and nil is encoded as the null sentinel (255).
    """
    @spec bool() :: StreamData.t(boolean() | nil)
    def bool, do: one_of([boolean(), constant(nil)])

    @doc "Generator for non-nullable booleans (true/false only)"
    @spec non_nullable_bool() :: StreamData.t(boolean())
    def non_nullable_bool, do: boolean()

    @doc """
    Generator for UTF-8 strings up to 1000 bytes.

    Uses ASCII characters only to ensure byte length == char length,
    avoiding issues with multi-byte UTF-8 characters exceeding limits.
    """
    @spec string() :: StreamData.t(String.t())
    def string do
      # Use ASCII only to guarantee byte length limits
      string(:ascii, min_length: 0, max_length: 1000)
    end

    @doc """
    Generator for short strings (up to 100 bytes).

    Uses ASCII characters only for predictable byte lengths.
    """
    @spec short_string() :: StreamData.t(String.t())
    def short_string do
      string(:ascii, min_length: 0, max_length: 100)
    end

    @doc """
    Generator for string8 values (up to 255 bytes).
    """
    @spec string8() :: StreamData.t(String.t())
    def string8 do
      string(:ascii, min_length: 0, max_length: 255)
    end

    @doc """
    Generator for string16 values (up to 65535 bytes).

    For practical testing, limits to 1000 bytes by default.
    """
    @spec string16(keyword()) :: StreamData.t(String.t())
    def string16(opts \\ []) do
      max = Keyword.get(opts, :max_length, 1000)
      string(:ascii, min_length: 0, max_length: max)
    end

    @doc false
    @spec default_string16() :: StreamData.t(String.t())
    def default_string16, do: string16()

    @doc """
    Generator for string32 values (up to ~4GB).

    For practical testing, limits to 10000 bytes by default.
    """
    @spec string32(keyword()) :: StreamData.t(String.t())
    def string32(opts \\ []) do
      max = Keyword.get(opts, :max_length, 10_000)
      string(:ascii, min_length: 0, max_length: max)
    end

    @doc false
    @spec default_string32() :: StreamData.t(String.t())
    def default_string32, do: string32()

    @doc "Generator for UUID strings (36-char dashed format)"
    @spec uuid_string() :: StreamData.t(String.t() | nil)
    def uuid_string do
      one_of([
        map(uuid(), &GridCodec.Types.UUIDString.format_uuid/1),
        constant(nil)
      ])
    end

    @doc "Generator for microsecond timestamps (nullable)"
    @spec timestamp_us() :: StreamData.t(integer() | nil)
    def timestamp_us do
      one_of([
        integer(1_577_836_800_000_000..1_893_456_000_000_000),
        integer(-1_000_000_000_000..-1),
        constant(nil)
      ])
    end

    @doc "Generator for nanosecond timestamps (nullable)"
    @spec timestamp_ns() :: StreamData.t(integer() | nil)
    def timestamp_ns do
      one_of([
        integer(1_577_836_800_000_000_000..1_893_456_000_000_000_000),
        integer(-1_000_000_000_000_000..-1),
        constant(nil)
      ])
    end

    @doc "Generator for DateTime (microsecond precision, nullable)"
    @spec datetime_us() :: StreamData.t(DateTime.t() | nil)
    def datetime_us do
      one_of([
        map(integer(1_577_836_800_000_000..1_893_456_000_000_000), fn us ->
          DateTime.from_unix!(us, :microsecond)
        end),
        constant(nil)
      ])
    end

    @doc "Generator for DateTime (nanosecond precision, nullable)"
    @spec datetime_ns() :: StreamData.t(DateTime.t() | nil)
    def datetime_ns do
      one_of([
        map(integer(1_577_836_800_000_000..1_893_456_000_000_000), fn us ->
          DateTime.from_unix!(us, :microsecond)
        end),
        constant(nil)
      ])
    end

    @doc "Generator for Decimal values (nullable, as {mantissa, exponent} tuples)"
    @spec decimal() :: StreamData.t(tuple() | nil)
    def decimal do
      one_of([
        bind(integer(-1_000_000_000..1_000_000_000), fn mantissa ->
          bind(integer(-8..8), fn exp ->
            constant({mantissa, exp})
          end)
        end),
        constant(nil)
      ])
    end

    @doc "Generator for positive Decimal values (nullable)"
    @spec positive_decimal() :: StreamData.t(tuple() | nil)
    def positive_decimal do
      one_of([
        bind(integer(0..1_000_000_000), fn mantissa ->
          bind(integer(-8..0), fn exp ->
            constant({mantissa, exp})
          end)
        end),
        constant(nil)
      ])
    end

    @doc "Generator for binary data of specified size"
    @spec binary(non_neg_integer()) :: StreamData.t(binary())
    def binary(size) when is_integer(size) and size >= 0 do
      map(
        list_of(integer(0..255), length: size),
        fn bytes -> :binary.list_to_bin(bytes) end
      )
    end

    # ============================================================================
    # Lookup and Dispatch
    # ============================================================================

    @doc """
    Returns a generator for the given type atom.

    Falls back to the type module's generator/0 if it exists.
    """
    @spec for_type(atom()) :: StreamData.t(term())
    def for_type(type_atom) when is_atom(type_atom) do
      case Map.fetch(@type_generators, type_atom) do
        {:ok, gen_fn} ->
          gen_fn.()

        :error ->
          # Try to get generator from type module
          case GridCodec.Type.lookup(type_atom) do
            {:ok, module} ->
              if function_exported?(module, :generator, 0) do
                module.generator()
              else
                raise ArgumentError,
                      "No generator for type #{inspect(type_atom)}. " <>
                        "Implement generator/0 in #{inspect(module)}"
              end

            {:error, :unknown_type} ->
              raise ArgumentError, "Unknown type: #{inspect(type_atom)}"
          end
      end
    end

    @doc """
    Returns a generator for a complete codec value map.

    Generates a map with all fields populated with valid values.
    """
    @spec for_codec(module()) :: StreamData.t(map())
    def for_codec(codec_module) when is_atom(codec_module) do
      schema = codec_module.__schema__()
      fields = schema.fields

      # Build a generator for each field
      field_generators =
        Enum.map(fields, fn {name, type, _opts} ->
          gen = for_type(type)
          {name, gen}
        end)

      # Combine into a map generator
      fixed_map(Map.new(field_generators))
    end

    # ============================================================================
    # Schema Generation (for meta-testing)
    # ============================================================================

    @fixed_types [:u8, :u16, :u32, :u64, :i8, :i16, :i32, :i64, :f32, :f64, :uuid, :bool]

    @doc """
    Generates random field definitions for testing codec generation.

    Returns a list of `{name, type, opts}` tuples.
    """
    @spec schema(keyword()) :: StreamData.t([{atom(), atom(), keyword()}])
    def schema(opts \\ []) do
      min_fields = Keyword.get(opts, :min_fields, 1)
      max_fields = Keyword.get(opts, :max_fields, 10)
      types = Keyword.get(opts, :types, @fixed_types)

      field_gen = field_definition(types)

      bind(integer(min_fields..max_fields), fn num_fields ->
        map(
          list_of(field_gen, length: num_fields),
          fn fields ->
            # Ensure unique field names
            fields
            |> Enum.with_index()
            |> Enum.map(fn {{_name, type, opts}, idx} ->
              {String.to_atom("field_#{idx}"), type, opts}
            end)
          end
        )
      end)
    end

    @doc """
    Generates a single field definition.
    """
    @spec field_definition([atom()]) :: StreamData.t({atom(), atom(), keyword()})
    def field_definition(types \\ @fixed_types) do
      tuple({
        field_name(),
        member_of(types),
        constant([])
      })
    end

    @doc """
    Generates valid field names.
    """
    @spec field_name() :: StreamData.t(atom())
    def field_name do
      map(
        string(:alphanumeric, min_length: 1, max_length: 20),
        fn str ->
          str
          |> String.downcase()
          |> String.replace(~r/^[0-9]/, "f")
          |> String.to_atom()
        end
      )
    end

    # ============================================================================
    # Property Test Helpers
    # ============================================================================

    @doc """
    Creates a generator for group entries.

    Takes a list of field definitions and returns a generator for entry maps.
    """
    @spec group_entry([{atom(), atom(), keyword()}]) :: StreamData.t(map())
    def group_entry(field_defs) do
      field_generators =
        Enum.map(field_defs, fn {name, type, _opts} ->
          {name, for_type(type)}
        end)

      fixed_map(Map.new(field_generators))
    end

    @doc """
    Creates a generator for a list of group entries.
    """
    @spec group_entries([{atom(), atom(), keyword()}], keyword()) :: StreamData.t([map()])
    def group_entries(field_defs, opts \\ []) do
      min = Keyword.get(opts, :min, 0)
      max = Keyword.get(opts, :max, 100)

      entry_gen = group_entry(field_defs)
      list_of(entry_gen, min_length: min, max_length: max)
    end
  end
end
