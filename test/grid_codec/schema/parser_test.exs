defmodule GridCodec.Schema.ParserTest do
  use ExUnit.Case, async: true

  alias GridCodec.Schema.Parser
  alias GridCodec.Schema.Parser.{CompositeType, EnumDef}

  describe "parse/1" do
    test "parses empty schema block" do
      content = """
      schema {
        id: 100
        version: 1
      }
      """

      assert {:ok, schema} = Parser.parse(content)
      assert schema.id == 100
      assert schema.version == 1
    end

    test "parses named schema block" do
      content = """
      schema Trading {
        id: 100
        version: 2
      }
      """

      assert {:ok, schema} = Parser.parse(content)
      assert schema.name == :Trading
      assert schema.id == 100
      assert schema.version == 2
    end

    test "parses simple struct with new syntax" do
      content = """
      schema { id: 1 }
      
      struct Order (template_id: 1001) {
        id: uuid_string
        user_id: u64
        quantity: u32
      }
      """

      assert {:ok, schema} = Parser.parse(content)
      assert Map.has_key?(schema.structs, :Order)

      struct_def = schema.structs[:Order]
      assert struct_def.template_id == 1001
      assert length(struct_def.fields) == 3

      [f1, f2, f3] = struct_def.fields
      assert f1.name == :id
      assert f1.type == :uuid_string
      assert f2.name == :user_id
      assert f2.type == :u64
      assert f3.name == :quantity
      assert f3.type == :u32
    end

    test "parses struct with version override" do
      content = """
      schema { id: 1 version: 1 }
      
      struct Order (template_id: 1001, version: 2) {
        id: uuid_string
      }
      """

      assert {:ok, schema} = Parser.parse(content)
      struct_def = schema.structs[:Order]
      
      assert struct_def.template_id == 1001
      assert struct_def.version == 2
    end

    test "parses struct with group" do
      content = """
      schema { id: 1 }
      
      struct Order (template_id: 1001) {
        id: uuid_string
        
        group fills {
          price: u64
          qty: u32
        }
      }
      """

      assert {:ok, schema} = Parser.parse(content)
      struct_def = schema.structs[:Order]

      assert length(struct_def.fields) == 1
      assert length(struct_def.groups) == 1

      [group] = struct_def.groups
      assert group.name == :fills
      assert length(group.fields) == 2
    end

    test "parses composite type" do
      content = """
      schema { id: 1 }
      
      type Price {
        mantissa: i64
        exponent: i8
      }
      """

      assert {:ok, schema} = Parser.parse(content)
      assert Map.has_key?(schema.types, :Price)

      type = schema.types[:Price]
      assert %CompositeType{} = type
      assert length(type.fields) == 2

      [f1, f2] = type.fields
      assert f1.name == :mantissa
      assert f1.type == :i64
      assert f2.name == :exponent
      assert f2.type == :i8
    end

    test "parses enum" do
      content = """
      schema { id: 1 }
      
      enum Side : u8 {
        buy = 1
        sell = 2
      }
      """

      assert {:ok, schema} = Parser.parse(content)
      assert Map.has_key?(schema.enums, :Side)

      enum = schema.enums[:Side]
      assert %EnumDef{} = enum
      assert enum.underlying_type == :u8
      assert enum.values == [buy: 1, sell: 2]
    end

    test "parses optional fields" do
      content = """
      schema { id: 1 }
      
      struct Order (template_id: 1001) {
        id: uuid_string
        notes?: string16
      }
      """

      assert {:ok, schema} = Parser.parse(content)
      struct_def = schema.structs[:Order]

      [f1, f2] = struct_def.fields
      assert f1.optional == false
      assert f2.name == :notes
      assert f2.optional == true
    end

    test "parses comments" do
      content = """
      # This is a comment
      schema { id: 1 }  # inline comment
      
      # Another comment
      struct Order (template_id: 1001) {
        id: uuid_string  # field comment
      }
      """

      assert {:ok, schema} = Parser.parse(content)
      assert schema.id == 1
      assert Map.has_key?(schema.structs, :Order)
    end

    test "parses multiple structs" do
      content = """
      schema { id: 100 }
      
      struct Order (template_id: 1001) {
        id: uuid_string
      }
      
      struct Trade (template_id: 1002) {
        trade_id: uuid_string
        order_id: uuid_string
      }
      """

      assert {:ok, schema} = Parser.parse(content)
      assert map_size(schema.structs) == 2
      assert Map.has_key?(schema.structs, :Order)
      assert Map.has_key?(schema.structs, :Trade)
    end

    test "parses complete schema" do
      content = """
      schema Trading {
        id: 100
        version: 1
      }
      
      type Price {
        mantissa: i64
        exponent: i8
      }
      
      enum Side : u8 {
        buy = 1
        sell = 2
      }
      
      struct Order (template_id: 1001) {
        id: uuid_string
        user_id: u64
        side: Side
        price: Price
        quantity: u32
        
        group fills {
          fill_price: u64
          fill_qty: u32
        }
      }
      
      struct Trade (template_id: 1002, version: 2) {
        trade_id: uuid_string
        order_id: uuid_string
        price: u64
        quantity: u32
      }
      """

      assert {:ok, schema} = Parser.parse(content)
      
      assert schema.name == :Trading
      assert schema.id == 100
      assert schema.version == 1
      
      assert map_size(schema.types) == 1
      assert map_size(schema.enums) == 1
      assert map_size(schema.structs) == 2
      
      # Check version override
      assert schema.structs[:Order].version == nil  # inherits from schema
      assert schema.structs[:Trade].version == 2    # overridden
    end

    test "legacy message syntax still works" do
      content = """
      schema { id: 1 }
      message Order (1001) {
        id: uuid_string
      }
      """

      assert {:ok, schema} = Parser.parse(content)
      assert Map.has_key?(schema.structs, :Order)
      assert schema.structs[:Order].template_id == 1001
    end
  end

  describe "parse_file/1" do
    test "returns error for missing file" do
      assert {:error, {:file_error, "nonexistent.grid", :enoent}} = 
        Parser.parse_file("nonexistent.grid")
    end
  end
end
