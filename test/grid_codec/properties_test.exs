defmodule GridCodec.PropertiesTest do
  @moduledoc """
  Property-based tests for GridCodec codec behavior.

  These tests verify core properties that must hold for all codecs:

  1. **Roundtrip Safety**: encode(x) |> decode() == x
  2. **Deterministic Encoding**: encode(x) always produces the same binary
  3. **Binary Size Predictability**: block_length() matches actual fixed block
  4. **Zero-Copy Consistency**: get(wrap(binary), field) == decode(binary)[field]
  5. **Type Boundary Correctness**: Values at type boundaries encode/decode correctly

  Module-specific property tests are in their respective test files:
  - Group tests: `test/grid_codec/group_test.exs`
  - String tests: `test/grid_codec/types/string_test.exs`
  - Header tests: `test/grid_codec/header_test.exs`
  """

  use ExUnit.Case, async: true
  use ExUnitProperties

  alias GridCodec.Generators

  # ============================================================================
  # Type-Level Roundtrip Properties
  # ============================================================================

  describe "type roundtrip properties" do
    @fixed_types [:u8, :u16, :u32, :u64, :i8, :i16, :i32, :i64, :bool, :uuid]

    for type <- @fixed_types do
      property "#{type} values roundtrip through encode/decode" do
        # Define a simple codec for this type
        defmodule :"#{__MODULE__}.#{String.capitalize(to_string(unquote(type)))}Codec" do
          use GridCodec

          defcodec do
            field :value, unquote(type)
          end
        end

        codec = :"#{__MODULE__}.#{String.capitalize(to_string(unquote(type)))}Codec"
        gen = Generators.for_type(unquote(type))

        check all(value <- gen, max_runs: 100) do
          data = %{value: value}
          binary = codec.encode(data)
          {:ok, decoded} = codec.decode(binary)

          assert decoded.value == value,
                 "Roundtrip failed for #{unquote(type)}: #{inspect(value)} != #{inspect(decoded.value)}"
        end
      end
    end

    property "f32 values roundtrip (within precision)" do
      defmodule F32Codec do
        use GridCodec

        defcodec do
          field :value, :f32
        end
      end

      check all(value <- Generators.f32(), max_runs: 100) do
        data = %{value: value}
        binary = F32Codec.encode(data)
        {:ok, decoded} = F32Codec.decode(binary)

        assert_in_delta decoded.value, value, abs(value * 1.0e-6) + 1.0e-6
      end
    end

    property "f64 values roundtrip (within precision)" do
      defmodule F64Codec do
        use GridCodec

        defcodec do
          field :value, :f64
        end
      end

      check all(value <- Generators.f64(), max_runs: 100) do
        data = %{value: value}
        binary = F64Codec.encode(data)
        {:ok, decoded} = F64Codec.decode(binary)

        assert_in_delta decoded.value, value, abs(value * 1.0e-14) + 1.0e-14
      end
    end
  end

  # ============================================================================
  # Multi-Field Codec Properties
  # ============================================================================

  describe "multi-field codec properties" do
    defmodule MultiFieldCodec do
      use GridCodec

      defcodec do
        field :id, :u64
        field :count, :u32
        field :score, :i32
        field :active, :bool
        field :ratio, :f64
        field :uuid, :uuid
      end
    end

    property "multi-field codec roundtrips" do
      gen =
        StreamData.fixed_map(%{
          id: Generators.u64(),
          count: Generators.u32(),
          score: Generators.i32(),
          active: Generators.bool(),
          ratio: Generators.f64(),
          uuid: Generators.uuid()
        })

      check all(data <- gen, max_runs: 100) do
        binary = MultiFieldCodec.encode(data)
        {:ok, decoded} = MultiFieldCodec.decode(binary)

        assert decoded.id == data.id
        assert decoded.count == data.count
        assert decoded.score == data.score
        assert decoded.active == data.active
        assert_in_delta decoded.ratio, data.ratio, abs(data.ratio * 1.0e-14) + 1.0e-14
        assert decoded.uuid == data.uuid
      end
    end

    property "binary size matches block_length" do
      gen =
        StreamData.fixed_map(%{
          id: Generators.u64(),
          count: Generators.u32(),
          score: Generators.i32(),
          active: Generators.bool(),
          ratio: Generators.f64(),
          uuid: Generators.uuid()
        })

      check all(data <- gen, max_runs: 50) do
        binary = MultiFieldCodec.encode(data)
        assert byte_size(binary) == MultiFieldCodec.block_length()
      end
    end

    property "deterministic encoding" do
      gen =
        StreamData.fixed_map(%{
          id: Generators.u64(),
          count: Generators.u32(),
          score: Generators.i32(),
          active: Generators.bool(),
          ratio: Generators.f64(),
          uuid: Generators.uuid()
        })

      check all(data <- gen, max_runs: 50) do
        binary1 = MultiFieldCodec.encode(data)
        binary2 = MultiFieldCodec.encode(data)
        assert binary1 == binary2
      end
    end
  end

  # ============================================================================
  # Zero-Copy Access Properties
  # ============================================================================

  describe "zero-copy access properties" do
    defmodule ZeroCopyCodec do
      use GridCodec

      defcodec do
        field :a, :u64
        field :b, :u32
        field :c, :i16
        field :d, :bool
        field :e, :uuid
      end
    end

    property "get/2 returns same value as full decode" do
      gen =
        StreamData.fixed_map(%{
          a: Generators.u64(),
          b: Generators.u32(),
          c: Generators.i16(),
          d: Generators.bool(),
          e: Generators.uuid()
        })

      check all(data <- gen, max_runs: 100) do
        binary = ZeroCopyCodec.encode(data)
        env = ZeroCopyCodec.wrap(binary)
        {:ok, decoded} = ZeroCopyCodec.decode(binary)

        assert ZeroCopyCodec.get(env, :a) == decoded.a
        assert ZeroCopyCodec.get(env, :b) == decoded.b
        assert ZeroCopyCodec.get(env, :c) == decoded.c
        assert ZeroCopyCodec.get(env, :d) == decoded.d
        assert ZeroCopyCodec.get(env, :e) == decoded.e
      end
    end

    property "envelope preserves binary reference" do
      gen =
        StreamData.fixed_map(%{
          a: Generators.u64(),
          b: Generators.u32(),
          c: Generators.i16(),
          d: Generators.bool(),
          e: Generators.uuid()
        })

      check all(data <- gen, max_runs: 50) do
        binary = ZeroCopyCodec.encode(data)
        env = ZeroCopyCodec.wrap(binary)

        assert GridCodec.Envelope.binary(env) == binary
      end
    end
  end

  # ============================================================================
  # Type Boundary Properties
  # ============================================================================

  describe "type boundary properties" do
    # Note: The max values are null sentinels (reserved for nil), so we test max-1
    property "unsigned integers encode at boundaries" do
      check all(
              {type, min, max} <-
                StreamData.member_of([
                  # Max values are null sentinels, test max-1 instead
                  {:u8, 0, 254},
                  {:u16, 0, 65_534},
                  {:u32, 0, 4_294_967_294},
                  {:u64, 0, 18_446_744_073_709_551_614}
                ]),
              value <- StreamData.member_of([min, max]),
              max_runs: 20
            ) do
        codec_mod = define_single_field_codec(type)
        data = %{value: value}
        binary = codec_mod.encode(data)
        {:ok, decoded} = codec_mod.decode(binary)
        assert decoded.value == value
      end
    end

    property "signed integers encode at boundaries" do
      check all(
              {type, min, max} <-
                StreamData.member_of([
                  # Min values are null sentinels, test min+1 instead
                  {:i8, -127, 127},
                  {:i16, -32_767, 32_767},
                  {:i32, -2_147_483_647, 2_147_483_647},
                  {:i64, -9_223_372_036_854_775_807, 9_223_372_036_854_775_807}
                ]),
              value <- StreamData.member_of([min, max]),
              max_runs: 20
            ) do
        codec_mod = define_single_field_codec(type)
        data = %{value: value}
        binary = codec_mod.encode(data)
        {:ok, decoded} = codec_mod.decode(binary)
        assert decoded.value == value
      end
    end
  end

  # ============================================================================
  # Schema Introspection Properties
  # ============================================================================

  describe "schema introspection properties" do
    alias __MODULE__.MultiFieldCodec

    test "__fields__/0 returns correct field names for multi-field codec" do
      # MultiFieldCodec has: id(u64), count(u32), score(i32), active(bool), ratio(f64), uuid(uuid)
      assert MultiFieldCodec.__fields__() == [:id, :count, :score, :active, :ratio, :uuid]
    end

    test "__schema__/0 returns valid schema metadata" do
      schema = MultiFieldCodec.__schema__()

      assert is_integer(schema.version)
      assert schema.endian in [:little, :big]
      assert is_integer(schema.block_length)
      assert is_list(schema.fixed_fields)
      assert is_list(schema.var_fields)
      assert is_list(schema.fields)
    end

    test "block_length/0 matches sum of fixed field sizes" do
      # MultiFieldCodec has: u64(8) + u32(4) + i32(4) + bool(1) + f64(8) + uuid(16) = 41 bytes
      assert MultiFieldCodec.block_length() == 41
    end

    property "encoded binary has consistent size for fixed-field codecs" do
      gen =
        StreamData.fixed_map(%{
          id: Generators.u64(),
          count: Generators.u32(),
          score: Generators.i32(),
          active: Generators.bool(),
          ratio: Generators.f64(),
          uuid: Generators.uuid()
        })

      check all(data <- gen, max_runs: 50) do
        binary = MultiFieldCodec.encode(data)
        assert byte_size(binary) == MultiFieldCodec.block_length()
      end
    end
  end

  # ============================================================================
  # Helpers
  # ============================================================================

  @type_codecs %{}

  defp define_single_field_codec(type) do
    case Map.get(@type_codecs, type) do
      nil ->
        mod_name = :"#{__MODULE__}.Boundary#{String.capitalize(to_string(type))}Codec"

        unless Code.ensure_loaded?(mod_name) do
          Code.eval_string("""
          defmodule #{inspect(mod_name)} do
            use GridCodec

            defcodec do
              field :value, #{inspect(type)}
            end
          end
          """)
        end

        mod_name

      mod ->
        mod
    end
  end
end
