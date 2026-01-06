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
end
