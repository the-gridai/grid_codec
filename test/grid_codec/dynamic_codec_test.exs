defmodule GridCodec.DynamicCodecTest do
  @moduledoc """
  Tests for dynamically generated codecs.

  These tests verify that codecs generated with random schemas work correctly.
  This tests the meta-level correctness of the codec framework itself.
  """

  use ExUnit.Case, async: false
  use ExUnitProperties

  alias GridCodec.Generators

  @moduletag :dynamic

  describe "dynamically generated codecs" do
    property "random fixed-field schemas produce working codecs" do
      check all(
              schema <- Generators.schema(min_fields: 1, max_fields: 5),
              max_runs: 20
            ) do
        # Generate a unique module name
        mod_name = :"GridCodec.DynamicCodec#{:erlang.unique_integer([:positive])}"

        # Build the codec definition
        field_defs =
          Enum.map(schema, fn {name, type, _opts} ->
            "field :#{name}, :#{type}"
          end)
          |> Enum.join("\n      ")

        code = """
        defmodule #{inspect(mod_name)} do
          use GridCodec

          defcodec do
            #{field_defs}
          end
        end
        """

        # Compile the module
        Code.compile_string(code)

        # Generate valid data for this schema
        data =
          Map.new(schema, fn {name, type, _opts} ->
            [value] = Enum.take(Generators.for_type(type), 1)
            {name, value}
          end)

        # Test roundtrip
        binary = mod_name.encode(data)
        {:ok, decoded} = mod_name.decode(binary)

        # Verify each field (with float tolerance)
        for {name, type, _opts} <- schema do
          original = Map.get(data, name)
          result = Map.get(decoded, name)

          if type in [:f32, :f64] do
            assert_in_delta result, original, abs(original * 1.0e-6) + 1.0e-6
          else
            assert result == original,
                   "Field #{name} (#{type}): expected #{inspect(original)}, got #{inspect(result)}"
          end
        end
      end
    end

    property "codec block_length matches schema field sizes" do
      check all(
              schema <- Generators.schema(min_fields: 1, max_fields: 5),
              max_runs: 20
            ) do
        mod_name = :"GridCodec.DynamicCodec#{:erlang.unique_integer([:positive])}"

        field_defs =
          Enum.map(schema, fn {name, type, _opts} ->
            "field :#{name}, :#{type}"
          end)
          |> Enum.join("\n      ")

        code = """
        defmodule #{inspect(mod_name)} do
          use GridCodec

          defcodec do
            #{field_defs}
          end
        end
        """

        Code.compile_string(code)

        # Calculate expected size
        expected_size =
          Enum.reduce(schema, 0, fn {_name, type, _opts}, acc ->
            acc + GridCodec.Type.size(type)
          end)

        assert mod_name.block_length() == expected_size
      end
    end

    property "codec zero-copy access matches full decode" do
      check all(
              schema <- Generators.schema(min_fields: 2, max_fields: 4),
              max_runs: 15
            ) do
        mod_name = :"GridCodec.DynamicCodec#{:erlang.unique_integer([:positive])}"

        field_defs =
          Enum.map(schema, fn {name, type, _opts} ->
            "field :#{name}, :#{type}"
          end)
          |> Enum.join("\n      ")

        code = """
        defmodule #{inspect(mod_name)} do
          use GridCodec

          defcodec do
            #{field_defs}
          end
        end
        """

        Code.compile_string(code)

        data =
          Map.new(schema, fn {name, type, _opts} ->
            [value] = Enum.take(Generators.for_type(type), 1)
            {name, value}
          end)

        binary = mod_name.encode(data)
        env = mod_name.wrap(binary)
        {:ok, decoded} = mod_name.decode(binary)

        for {name, type, _opts} <- schema do
          zero_copy_value = mod_name.get(env, name)
          decoded_value = Map.get(decoded, name)

          if type in [:f32, :f64] do
            assert_in_delta zero_copy_value, decoded_value, 1.0e-10
          else
            assert zero_copy_value == decoded_value,
                   "Zero-copy mismatch for #{name}: #{inspect(zero_copy_value)} != #{inspect(decoded_value)}"
          end
        end
      end
    end
  end

  describe "schema introspection" do
    property "schema metadata is correct" do
      check all(
              schema <- Generators.schema(min_fields: 1, max_fields: 5),
              max_runs: 10
            ) do
        mod_name = :"GridCodec.DynamicCodec#{:erlang.unique_integer([:positive])}"

        field_defs =
          Enum.map(schema, fn {name, type, _opts} ->
            "field :#{name}, :#{type}"
          end)
          |> Enum.join("\n      ")

        code = """
        defmodule #{inspect(mod_name)} do
          use GridCodec

          defcodec do
            #{field_defs}
          end
        end
        """

        Code.compile_string(code)

        meta = mod_name.__schema__()

        assert meta.version == 1
        assert meta.endian == :little
        assert length(meta.fields) == length(schema)

        for {{name, type, _opts}, {meta_name, meta_type, _meta_opts}} <-
              Enum.zip(schema, meta.fields) do
          assert meta_name == name
          assert meta_type == type
        end
      end
    end
  end

  describe "edge cases" do
    test "empty data map with defaults works" do
      defmodule EmptyDefaultCodec do
        use GridCodec

        defcodec do
          field :count, :u32, default: 0
          field :flag, :bool, default: false
        end
      end

      # Encoding with empty map should use defaults
      binary = EmptyDefaultCodec.encode(%{})

      # Should be able to decode
      {:ok, decoded} = EmptyDefaultCodec.decode(binary)
      assert decoded.count == 0
      assert decoded.flag == false
    end

    test "single field codec works" do
      defmodule SingleFieldCodec do
        use GridCodec

        defcodec do
          field :value, :u64
        end
      end

      data = %{value: 12345}
      binary = SingleFieldCodec.encode(data)
      {:ok, decoded} = SingleFieldCodec.decode(binary)

      assert decoded.value == 12345
      assert byte_size(binary) == 8
    end

    test "all integer types in one codec" do
      defmodule AllIntegersCodec do
        use GridCodec

        defcodec do
          field :u8_val, :u8
          field :u16_val, :u16
          field :u32_val, :u32
          field :u64_val, :u64
          field :i8_val, :i8
          field :i16_val, :i16
          field :i32_val, :i32
          field :i64_val, :i64
        end
      end

      # Note: Null sentinels are reserved for nil:
      # - unsigned max values (255, 65535, etc.)
      # - signed min values (-128, -32768, etc.)
      # Use valid boundary values instead
      data = %{
        u8_val: 254,
        u16_val: 65534,
        u32_val: 4_294_967_294,
        u64_val: 18_446_744_073_709_551_614,
        i8_val: -127,
        i16_val: -32767,
        i32_val: -2_147_483_647,
        i64_val: -9_223_372_036_854_775_807
      }

      binary = AllIntegersCodec.encode(data)
      {:ok, decoded} = AllIntegersCodec.decode(binary)

      assert decoded == data
      # 1 + 2 + 4 + 8 + 1 + 2 + 4 + 8 = 30 bytes
      assert byte_size(binary) == 30
    end
  end
end
