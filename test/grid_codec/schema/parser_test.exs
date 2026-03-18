defmodule GridCodec.Schema.ParserTest do
  use ExUnit.Case, async: true

  alias GridCodec.Schema.Parser
  alias GridCodec.Schema.Parser.EnumDef
  alias GridCodec.Schema.Parser.TypeDef

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
      assert %TypeDef{kind: :composite} = type
      assert length(type.fields) == 2

      [f1, f2] = type.fields
      assert f1.name == :mantissa
      assert f1.type == :i64
      assert f2.name == :exponent
      assert f2.type == :i8
    end

    test "parses prefixed_id block" do
      content = """
      schema { id: 1 }

      prefixed_id UserId {
        prefix: "user"
        tag: 1
      }
      """

      assert {:ok, schema} = Parser.parse(content)
      assert Map.has_key?(schema.types, :UserId)

      type = schema.types[:UserId]
      assert %TypeDef{kind: :prefixed_id} = type
      assert type.params == %{prefix: "user", tag: 1}
    end

    test "parses char_array block" do
      content = """
      schema { id: 1 }

      char_array Symbol {
        length: 8
      }
      """

      assert {:ok, schema} = Parser.parse(content)
      assert Map.has_key?(schema.types, :Symbol)

      type = schema.types[:Symbol]
      assert %TypeDef{kind: :char_array} = type
      assert type.params == %{length: 8}
    end

    test "parses bitset block" do
      content = """
      schema { id: 1 }

      bitset Permissions : u8 {
        read = 0
        write = 1
        execute = 2
      }
      """

      assert {:ok, schema} = Parser.parse(content)
      assert Map.has_key?(schema.types, :Permissions)

      type = schema.types[:Permissions]
      assert %TypeDef{kind: :bitset} = type
      assert type.underlying_type == :u8
      assert type.values == [read: 0, write: 1, execute: 2]
    end

    test "custom types are referenced by struct fields" do
      content = """
      schema { id: 1 }

      prefixed_id UserId {
        prefix: "user"
        tag: 1
      }

      char_array Symbol {
        length: 8
      }

      struct UserCreated (template_id: 1001) {
        user_id: UserId
        name: Symbol
      }
      """

      assert {:ok, schema} = Parser.parse(content)
      assert Map.has_key?(schema.types, :UserId)
      assert Map.has_key?(schema.types, :Symbol)
      struct_def = schema.structs[:UserCreated]
      [f1, f2] = struct_def.fields
      assert f1.type == :UserId
      assert f2.type == :Symbol
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

    test "parses field, group, and enum docs" do
      content = """
      schema { id: 1 }

      enum Side : u8 {
        buy = 0, doc: "Bid-side order."
        sell = 1, doc: "Ask-side order."
      }

      struct Order (template_id: 1001) {
        side: Side, doc: "Current side."

        group fills {
          doc: "Partial fills."
          qty: u32, doc: "Executed quantity."
        }
      }
      """

      assert {:ok, schema} = Parser.parse(content)

      [buy, sell] = schema.enums[:Side].values
      assert buy == {:buy, 0, "Bid-side order."}
      assert sell == {:sell, 1, "Ask-side order."}

      struct_def = schema.structs[:Order]
      [field] = struct_def.fields
      assert field.name == :side
      assert field.doc == "Current side."

      [group] = struct_def.groups
      assert group.doc == "Partial fills."
      [group_field] = group.fields
      assert group_field.doc == "Executed quantity."
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
        |> Enum.map_join("\n", fn idx -> "field_#{idx}: u64" end)

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

  describe "custom type round-trip (parse -> format -> re-parse)" do
    test "prefixed_id round-trips" do
      content = """
      @syntax 1
      schema T { id: 1 version: 1 }

      prefixed_id UserId {
        prefix: "user"
        tag: 1
      }
      """

      assert {:ok, schema1} = Parser.parse(content)
      type1 = schema1.types[:UserId]
      assert type1.kind == :prefixed_id
      assert type1.params.prefix == "user"
      assert type1.params.tag == 1
    end

    test "char_array round-trips" do
      content = """
      @syntax 1
      schema T { id: 1 version: 1 }

      char_array Symbol {
        length: 8
      }
      """

      assert {:ok, schema1} = Parser.parse(content)
      type1 = schema1.types[:Symbol]
      assert type1.kind == :char_array
      assert type1.params.length == 8
    end

    test "bitset round-trips" do
      content = """
      @syntax 1
      schema T { id: 1 version: 1 }

      bitset Perms : u8 {
        read = 0
        write = 1
        execute = 2
      }
      """

      assert {:ok, schema1} = Parser.parse(content)
      type1 = schema1.types[:Perms]
      assert type1.kind == :bitset
      assert type1.underlying_type == :u8
      assert type1.values == [read: 0, write: 1, execute: 2]
    end
  end

  describe "WireSizes.resolve/2 for custom TypeDef kinds" do
    alias GridCodec.Breaking.WireSizes

    test "prefixed_id resolves to 17 bytes" do
      types = %{
        UserId: %TypeDef{name: :UserId, kind: :prefixed_id, params: %{prefix: "user", tag: 1}}
      }

      assert WireSizes.resolve(:UserId, types) == 17
    end

    test "char_array resolves to its length" do
      types = %{Symbol: %TypeDef{name: :Symbol, kind: :char_array, params: %{length: 8}}}
      assert WireSizes.resolve(:Symbol, types) == 8
    end

    test "bitset u8 resolves to 1 byte" do
      types = %{Perms: %TypeDef{name: :Perms, kind: :bitset, underlying_type: :u8, values: []}}
      assert WireSizes.resolve(:Perms, types) == 1
    end

    test "bitset u16 resolves to 2 bytes" do
      types = %{Flags: %TypeDef{name: :Flags, kind: :bitset, underlying_type: :u16, values: []}}
      assert WireSizes.resolve(:Flags, types) == 2
    end

    test "bitset u32 resolves to 4 bytes" do
      types = %{
        BigFlags: %TypeDef{name: :BigFlags, kind: :bitset, underlying_type: :u32, values: []}
      }

      assert WireSizes.resolve(:BigFlags, types) == 4
    end

    test "composite type still works" do
      alias GridCodec.Schema.Parser.Field
      fields = [%Field{name: :a, type: :u32}, %Field{name: :b, type: :i64}]
      types = %{Price: %TypeDef{name: :Price, kind: :composite, fields: fields}}
      assert WireSizes.resolve(:Price, types) == 12
    end
  end
end
