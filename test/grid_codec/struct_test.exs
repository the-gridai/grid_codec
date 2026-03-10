defmodule GridCodec.StructTest do
  use ExUnit.Case, async: true
  import Bitwise

  describe "defstruct generation" do
    defmodule BasicStruct do
      use GridCodec.Struct, template_id: 1, schema_id: 100

      defcodec do
        field :id, :u64
        field :name, :u32
      end
    end

    test "generates struct with correct fields" do
      struct = %BasicStruct{}
      assert Map.has_key?(struct, :id)
      assert Map.has_key?(struct, :name)
      assert struct.id == nil
      assert struct.name == nil
    end

    test "struct can be created with values" do
      struct = %BasicStruct{id: 123, name: 456}
      assert struct.id == 123
      assert struct.name == 456
    end
  end

  describe "default values" do
    defmodule DefaultsStruct do
      use GridCodec.Struct, template_id: 2, schema_id: 100

      defcodec do
        field :id, :u64
        field :count, :u32, default: 0
        field :status, :u8, default: 1
      end
    end

    test "struct fields have correct default values" do
      struct = %DefaultsStruct{}
      assert struct.id == nil
      assert struct.count == 0
      assert struct.status == 1
    end

    test "struct can override defaults" do
      struct = %DefaultsStruct{count: 100, status: 2}
      assert struct.count == 100
      assert struct.status == 2
    end
  end

  describe "enforce_keys" do
    defmodule RequiredFieldsStruct do
      use GridCodec.Struct, template_id: 3, schema_id: 100

      defcodec do
        field :id, :uuid, presence: :required
        field :price, :u64, presence: :required
        field :quantity, :u32, default: 0
      end
    end

    test "required fields must be provided" do
      assert_raise ArgumentError, ~r/the following keys must also be given/, fn ->
        struct!(RequiredFieldsStruct, quantity: 10)
      end
    end

    test "struct can be created when required fields are provided" do
      uuid = <<1::128>>
      struct = %RequiredFieldsStruct{id: uuid, price: 100}
      assert struct.id == uuid
      assert struct.price == 100
      assert struct.quantity == 0
    end
  end

  describe "constant fields" do
    defmodule ConstantFieldStruct do
      use GridCodec.Struct, template_id: 4, schema_id: 100

      defcodec do
        field :id, :u64
        field :version, :u8, presence: :constant, value: 1
      end
    end

    test "constant fields have their value as default" do
      struct = %ConstantFieldStruct{}
      assert struct.version == 1
    end

    test "constant fields can be overridden in struct (encoding uses constant)" do
      struct = %ConstantFieldStruct{version: 99}
      assert struct.version == 99
    end
  end

  describe "%__MODULE__{} in function heads" do
    defmodule StructPatternMatch do
      use GridCodec.Struct, template_id: 50, schema_id: 100

      defcodec do
        field :price, :u64, default: 0
        field :quantity, :u32, default: 0
      end

      def validate(%__MODULE__{price: p, quantity: q}) when p > 0 and q > 0, do: :ok
      def validate(%__MODULE__{}), do: {:error, :invalid}

      def total(%__MODULE__{price: p, quantity: q}), do: p * q
    end

    test "pattern matching on %__MODULE__{} works in function heads" do
      assert StructPatternMatch.validate(%StructPatternMatch{price: 100, quantity: 5}) == :ok

      assert StructPatternMatch.validate(%StructPatternMatch{price: 0, quantity: 5}) ==
               {:error, :invalid}

      assert StructPatternMatch.validate(%StructPatternMatch{}) == {:error, :invalid}
    end

    test "field extraction via %__MODULE__{} works" do
      assert StructPatternMatch.total(%StructPatternMatch{price: 10, quantity: 3}) == 30
    end

    test "encode/decode still works after struct pattern match functions" do
      struct = %StructPatternMatch{price: 100, quantity: 5}
      assert {:ok, binary} = StructPatternMatch.encode(struct)
      assert {:ok, decoded} = StructPatternMatch.decode(binary)
      assert decoded.price == 100
      assert decoded.quantity == 5
    end
  end

  describe "introspection functions" do
    defmodule IntrospectionStruct do
      use GridCodec.Struct, template_id: 5, schema_id: 200, version: 2

      defcodec do
        field :id, :uuid
        field :value, :u64
      end
    end

    test "__template_id__/0 returns template id" do
      assert IntrospectionStruct.__template_id__() == 5
    end

    test "__schema_id__/0 returns schema id" do
      assert IntrospectionStruct.__schema_id__() == 200
    end

    test "__version__/0 returns version" do
      assert IntrospectionStruct.__version__() == 2
    end

    test "__fields__/0 returns field names" do
      assert IntrospectionStruct.__fields__() == [:id, :value]
    end

    test "__gridcodec_struct__?/0 returns true" do
      assert IntrospectionStruct.__gridcodec_struct__?() == true
    end

    test "__schema__/0 returns schema metadata" do
      schema = IntrospectionStruct.__schema__()
      assert schema.template_id == 5
      assert schema.schema_id == 200
      assert schema.version == 2
    end
  end

  describe "auto template_id" do
    defmodule AutoTemplateIdStruct do
      use GridCodec.Struct, schema_id: 100

      defcodec do
        field :id, :u64
      end
    end

    test "template_id defaults to hash of module name" do
      expected = :erlang.phash2(AutoTemplateIdStruct) &&& 0xFFFF
      assert AutoTemplateIdStruct.__template_id__() == expected
    end
  end

  describe "mixed field types" do
    defmodule MixedFieldsStruct do
      use GridCodec.Struct, template_id: 6, schema_id: 100

      defcodec do
        field :uuid_field, :uuid, presence: :required
        field :u8_field, :u8, default: 0
        field :u16_field, :u16, default: 0
        field :u32_field, :u32, default: 0
        field :u64_field, :u64, default: 0
        field :i8_field, :i8, default: 0
        field :i16_field, :i16, default: 0
        field :i32_field, :i32, default: 0
        field :i64_field, :i64, default: 0
        field :bool_field, :bool, default: false
      end
    end

    test "struct supports all fixed-size field types" do
      uuid = <<1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16>>

      struct = %MixedFieldsStruct{
        uuid_field: uuid,
        u8_field: 255,
        u16_field: 65535,
        u32_field: 4_294_967_295,
        u64_field: 18_446_744_073_709_551_615,
        i8_field: -128,
        i16_field: -32768,
        i32_field: -2_147_483_648,
        i64_field: -9_223_372_036_854_775_808,
        bool_field: true
      }

      assert struct.uuid_field == uuid
      assert struct.u8_field == 255
      assert struct.u16_field == 65535
      assert struct.bool_field == true
    end
  end

  describe "typespec generation" do
    test "generates t/0 and layout/0 types by default" do
      assert has_type?(GridCodec.TestSupport.OrderEvent, :t, 0)
      assert has_type?(GridCodec.TestSupport.OrderEvent, :layout, 0)
      assert has_type?(GridCodec.TestSupport.OrderEvent, :framed_layout, 0)
    end

    test "can disable generated types with generate_typespec: false" do
      refute has_type?(GridCodec.TestSupport.OrderEventNoTypespec, :t, 0)
      refute has_type?(GridCodec.TestSupport.OrderEventNoTypespec, :layout, 0)
      refute has_type?(GridCodec.TestSupport.OrderEventNoTypespec, :framed_layout, 0)
    end

    test "fixed-size codecs get exact binary sizes for layout types" do
      block_bits = GridCodec.TestSupport.OrderEvent.__schema__().block_length * 8
      framed_bits = block_bits + 64

      assert {:type, _, :binary, [{:integer, _, ^block_bits}, {:integer, _, 0}]} =
               fetch_type_ast!(GridCodec.TestSupport.OrderEvent, :layout, 0)

      assert {:type, _, :binary, [{:integer, _, ^framed_bits}, {:integer, _, 0}]} =
               fetch_type_ast!(GridCodec.TestSupport.OrderEvent, :framed_layout, 0)
    end

    test "variable-size codecs get minimum size plus byte-aligned tail" do
      block_bits = GridCodec.TestSupport.OrderEventVar.__schema__().block_length * 8
      framed_bits = block_bits + 64

      assert {:type, _, :binary, [{:integer, _, ^block_bits}, {:integer, _, 8}]} =
               fetch_type_ast!(GridCodec.TestSupport.OrderEventVar, :layout, 0)

      assert {:type, _, :binary, [{:integer, _, ^framed_bits}, {:integer, _, 8}]} =
               fetch_type_ast!(GridCodec.TestSupport.OrderEventVar, :framed_layout, 0)
    end

    test "required fields in t/0 are non-nil" do
      id_type = fetch_struct_field_type_ast!(GridCodec.TestSupport.RequiredTypesStruct, :id)
      price_type = fetch_struct_field_type_ast!(GridCodec.TestSupport.RequiredTypesStruct, :price)

      quantity_type =
        fetch_struct_field_type_ast!(GridCodec.TestSupport.RequiredTypesStruct, :quantity)

      refute union_with_nil?(id_type)
      refute union_with_nil?(price_type)
      assert union_with_nil?(quantity_type)
    end

    test "constant fields in t/0 use literal type" do
      version_type =
        fetch_struct_field_type_ast!(GridCodec.TestSupport.ConstantTypesStruct, :version)

      assert {:integer, _, 1} = version_type
    end
  end

  defp has_type?(module, type_name, arity) do
    fetch_type_ast(module, type_name, arity) != nil
  end

  defp fetch_type_ast!(module, type_name, arity) do
    case fetch_type_ast(module, type_name, arity) do
      nil ->
        flunk("Could not find type #{inspect(type_name)}/#{arity} in #{inspect(module)}")

      ast ->
        ast
    end
  end

  defp fetch_type_ast(module, type_name, arity) do
    case Code.Typespec.fetch_types(module) do
      {:ok, types} ->
        Enum.find_value(types, fn
          {:type, {^type_name, type_ast, args}} when length(args) == arity -> type_ast
          {_, {^type_name, type_ast, args}} when length(args) == arity -> type_ast
          _ -> nil
        end)

      :error ->
        nil
    end
  end

  defp fetch_struct_field_type_ast!(module, field_name) do
    case fetch_type_ast!(module, :t, 0) do
      {:type, _, :map, fields} ->
        Enum.find_value(fields, fn
          {:type, _, :map_field_exact, [{:atom, _, ^field_name}, type_ast]} -> type_ast
          _ -> nil
        end) || flunk("Field #{inspect(field_name)} not found in #{inspect(module)}.t/0")

      other ->
        flunk("Unexpected t/0 AST for #{inspect(module)}: #{inspect(other)}")
    end
  end

  defp union_with_nil?({:type, _, :union, members}) do
    Enum.any?(members, &match?({:atom, _, nil}, &1))
  end

  defp union_with_nil?(_), do: false
end
