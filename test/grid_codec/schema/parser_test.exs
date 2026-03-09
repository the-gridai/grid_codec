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
      # inherits from schema
      assert schema.structs[:Order].version == nil
      # overridden
      assert schema.structs[:Trade].version == 2
    end

    test "legacy message syntax is rejected" do
      content = """
      schema { id: 1 }
      message Order (1001) {
        id: uuid_string
      }
      """

      assert {:error, {:unexpected_token, {:word, "message"}}} = Parser.parse(content)
    end
  end

  describe "parse_file/1" do
    test "returns error for missing file" do
      assert {:error, {:file_error, "nonexistent.grid", :enoent}} =
               Parser.parse_file("nonexistent.grid")
    end
  end

  describe "parser safety limits" do
    test "returns error when identifier count exceeds max_identifiers" do
      fields =
        1..20
        |> Enum.map(fn idx -> "field_#{idx}: u64" end)
        |> Enum.join("\n")

      content = """
      schema { id: 1 }
      struct Order (template_id: 1001) {
      #{fields}
      }
      """

      assert {:error, {:too_many_identifiers, count, 10}} =
               Parser.parse(content, max_identifiers: 10)

      assert count > 10
    end

    test "returns error when identifier length exceeds max_identifier_length" do
      long_name = String.duplicate("a", 40)

      content = """
      schema { id: 1 }
      struct #{long_name} (template_id: 1001) {
        id: u64
      }
      """

      assert {:error, {:identifier_too_long, ^long_name, 40, 16}} =
               Parser.parse(content, max_identifier_length: 16)
    end

    test "returns error for invalid identifier format" do
      content = """
      schema { id: 1 }
      struct Order (template_id: 1001) {
        bad-name: u64
      }
      """

      assert {:error, {:invalid_identifier, "bad-name"}} = Parser.parse(content)
    end
  end

  describe "import directive" do
    test "parses import directives" do
      content = """
      schema Trading {
        id: 100
        version: 1
      }

      import "order_created.grid"
      import "trade_executed.grid"
      """

      assert {:ok, schema} = Parser.parse(content)
      assert schema.imports == ["order_created.grid", "trade_executed.grid"]
      assert schema.id == 100
    end

    test "parses import with nested path" do
      content = """
      schema { id: 1 }
      import "other_schema/events/order_created.grid"
      """

      assert {:ok, schema} = Parser.parse(content)
      assert schema.imports == ["other_schema/events/order_created.grid"]
    end

    test "import coexists with inline definitions" do
      content = """
      schema { id: 1 }

      enum Side : u8 {
        buy = 0
        sell = 1
      }

      import "order.grid"
      """

      assert {:ok, schema} = Parser.parse(content)
      assert schema.imports == ["order.grid"]
      assert Map.has_key?(schema.enums, :Side)
    end
  end

  describe "files without schema block" do
    test "parses standalone struct" do
      content = """
      struct Order (template_id: 1001) {
        id: uuid_string
        price: u64
      }
      """

      assert {:ok, schema} = Parser.parse(content)
      assert schema.id == nil
      assert schema.name == nil
      assert Map.has_key?(schema.structs, :Order)
    end

    test "parses standalone enum" do
      content = """
      enum Side : u8 {
        buy = 0
        sell = 1
      }
      """

      assert {:ok, schema} = Parser.parse(content)
      assert schema.id == nil
      assert Map.has_key?(schema.enums, :Side)
    end
  end

  describe "parse_file_with_imports/2" do
    @tmp_dir Path.join(System.tmp_dir!(), "grid_parser_import_test")

    setup do
      dir = Path.join(@tmp_dir, "#{System.unique_integer([:positive])}")
      File.mkdir_p!(dir)
      on_exit(fn -> File.rm_rf!(dir) end)
      %{dir: dir}
    end

    test "resolves imports from files on disk", %{dir: dir} do
      File.write!(Path.join(dir, "order.grid"), """
      struct Order (template_id: 1) {
        id: u64
      }
      """)

      File.write!(Path.join(dir, "schema.grid"), """
      schema Test {
        id: 1
        version: 1
      }
      import "order.grid"
      """)

      assert {:ok, schema} = Parser.parse_file_with_imports(Path.join(dir, "schema.grid"))
      assert schema.id == 1
      assert Map.has_key?(schema.structs, :Order)
    end

    test "resolves nested imports", %{dir: dir} do
      File.mkdir_p!(Path.join(dir, "types"))

      File.write!(Path.join(dir, "types/side.grid"), """
      enum Side : u8 {
        buy = 0
        sell = 1
      }
      """)

      File.write!(Path.join(dir, "order.grid"), """
      struct Order (template_id: 1) {
        id: u64
      }
      """)

      File.write!(Path.join(dir, "schema.grid"), """
      schema Test {
        id: 1
        version: 1
      }
      import "order.grid"
      import "types/side.grid"
      """)

      assert {:ok, schema} = Parser.parse_file_with_imports(Path.join(dir, "schema.grid"))
      assert Map.has_key?(schema.structs, :Order)
      assert Map.has_key?(schema.enums, :Side)
    end

    test "detects circular imports", %{dir: dir} do
      File.write!(Path.join(dir, "a.grid"), """
      import "b.grid"
      """)

      File.write!(Path.join(dir, "b.grid"), """
      import "a.grid"
      """)

      assert {:error, {:circular_import, _}} =
               Parser.parse_file_with_imports(Path.join(dir, "a.grid"))
    end

    test "missing import file returns error", %{dir: dir} do
      File.write!(Path.join(dir, "schema.grid"), """
      schema Test { id: 1 }
      import "nonexistent.grid"
      """)

      assert {:error, {:file_error, _, :enoent}} =
               Parser.parse_file_with_imports(Path.join(dir, "schema.grid"))
    end
  end

  describe "@syntax directive" do
    test "parses @syntax 1" do
      content = """
      @syntax 1

      schema Trading {
        id: 100
        version: 1
      }
      """

      assert {:ok, schema} = Parser.parse(content)
      assert schema.syntax == 1
      assert schema.id == 100
    end

    test "defaults syntax to current when absent" do
      content = """
      schema { id: 1 }
      """

      assert {:ok, schema} = Parser.parse(content)
      assert schema.syntax == Parser.current_syntax()
    end

    test "rejects unsupported syntax version" do
      content = """
      @syntax 999

      schema { id: 1 }
      """

      assert {:error, {:unsupported_syntax, 999, _current}} = Parser.parse(content)
    end

    test "rejects invalid syntax version" do
      content = """
      @syntax abc

      schema { id: 1 }
      """

      assert {:error, {:invalid_syntax_version, "abc"}} = Parser.parse(content)
    end

    test "rejects unknown directive" do
      content = """
      @unknown 1

      schema { id: 1 }
      """

      assert {:error, {:unknown_directive, "unknown"}} = Parser.parse(content)
    end

    test "@syntax works with standalone struct" do
      content = """
      @syntax 1

      struct Order (template_id: 1001) {
        id: uuid_string
      }
      """

      assert {:ok, schema} = Parser.parse(content)
      assert schema.syntax == 1
      assert Map.has_key?(schema.structs, :Order)
    end

    test "@syntax works with imports" do
      content = """
      @syntax 1

      schema Test { id: 1 }
      import "other.grid"
      """

      assert {:ok, schema} = Parser.parse(content)
      assert schema.syntax == 1
      assert schema.imports == ["other.grid"]
    end

    test "current_syntax/0 returns expected version" do
      assert Parser.current_syntax() == 1
    end
  end

  describe "EBNF edge cases" do
    test "rejects ? in the middle of an identifier" do
      content = """
      struct Order (template_id: 1001) {
        f?oo: u64
      }
      """

      assert {:error, {:invalid_identifier, "f?oo"}} = Parser.parse(content)
    end

    test "allows trailing ? on field names (optional marker)" do
      content = """
      struct Order (template_id: 1001) {
        notes?: string16
      }
      """

      assert {:ok, schema} = Parser.parse(content)
      [field] = schema.structs[:Order].fields
      assert field.name == :notes
      assert field.optional == true
    end

    test "allows underscore-leading identifiers" do
      content = """
      struct Order (template_id: 1001) {
        _internal: u64
      }
      """

      assert {:ok, schema} = Parser.parse(content)
      [field] = schema.structs[:Order].fields
      assert field.name == :_internal
    end

    test "field named 'group' works with colon syntax" do
      content = """
      struct Order (template_id: 1001) {
        group: u64
      }
      """

      assert {:ok, schema} = Parser.parse(content)
      [field] = schema.structs[:Order].fields
      assert field.name == :group
      assert field.type == :u64
      assert schema.structs[:Order].groups == []
    end

    test "batch with empty any_of list is rejected" do
      content = """
      struct Order (template_id: 1001) {
        id: u64

        batch commands {
          any_of: []
          strategy: padded_union
        }
      }
      """

      assert {:error, {:empty_any_of}} = Parser.parse(content)
    end

    test "struct attributes without commas are rejected" do
      content = """
      struct Order (template_id: 1001 version: 2) {
        id: u64
      }
      """

      assert {:error, {:invalid_struct_attrs, _}} = Parser.parse(content)
    end

    test "negative integer value in field default" do
      content = """
      struct Order (template_id: 1001) {
        offset: i32, default: -1
      }
      """

      assert {:ok, schema} = Parser.parse(content)
      [field] = schema.structs[:Order].fields
      assert field.default == -1
    end

    test "multiple type parameters" do
      content = """
      struct Order (template_id: 1001) {
        price: decimal(scale: 8), wire_format: i64
      }
      """

      assert {:ok, schema} = Parser.parse(content)
      [field] = schema.structs[:Order].fields
      assert field.type == :decimal
      assert field.type_params == [scale: 8]
      assert field.wire_format == :i64
    end

    test "all field options together" do
      content = """
      struct Order (template_id: 1001) {
        exchange: string8, presence: constant, value: "NYSE", since: 2
      }
      """

      assert {:ok, schema} = Parser.parse(content)
      [field] = schema.structs[:Order].fields
      assert field.presence == :constant
      assert field.value == "NYSE"
      assert field.since == 2
    end
  end
end
