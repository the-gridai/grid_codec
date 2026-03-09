# credo:disable-for-this-file Credo.Check.Readability.ModuleDoc
defmodule GridCodec.CodecProofsTest do
  @moduledoc """
  Correctness proofs for GridCodec, expressed as property-based tests.

  Each property corresponds to a formal invariant of the codec system.
  For finite domains (enums, booleans, bitsets) these are **exhaustive proofs**.
  For infinite domains (integers, floats) these are probabilistic proofs
  with high confidence (~100 random samples per property by default).

  ## Properties Proved

  | ID  | Invariant                | Kind          |
  |-----|--------------------------|---------------|
  | P3  | Size consistency         | Probabilistic |
  | P6+ | Garbage rejection        | Probabilistic |
  | P7  | Type isolation           | Probabilistic |
  | P8  | Formatter/Parser agree   | Deterministic |
  | P9  | Byte-level idempotence   | Probabilistic |
  | P10 | Enum exhaustiveness      | **Exhaustive** |
  | P11 | Parser EBNF compliance   | Deterministic |
  """

  use ExUnit.Case, async: true
  use ExUnitProperties

  @header_size GridCodec.Header.size()

  # Codecs with full generator support via GridCodec.Generators.for_codec/1.
  # Types that lack generators (uuid_string, timestamp_us, datetime_us,
  # decimal, positive_decimal, string16) are excluded here but covered
  # by the existing zero_surprise property suite which uses hand-built generators.
  @generatable_codecs [
    GridCodec.ZSEdge.EnumCodec,
    GridCodec.ZSEdge.BitsetCodec,
    GridCodec.ZSEdge.CharCodec,
    GridCodec.ZSEdge.IntegerCodec,
    GridCodec.ZSEdge.F64Codec
  ]

  # ═══════════════════════════════════════════════════════════════════════
  # P3: Size Consistency
  #
  # For every valid struct of a fixed-size codec:
  #   byte_size(encode(x)) == header_size + block_length
  #
  # This is a necessary condition for wire compatibility: any receiver
  # can trust block_length in the header to skip/slice the message.
  # ═══════════════════════════════════════════════════════════════════════

  for codec <- [
        GridCodec.ZSEdge.EnumCodec,
        GridCodec.ZSEdge.BitsetCodec,
        GridCodec.ZSEdge.CharCodec,
        GridCodec.ZSEdge.IntegerCodec,
        GridCodec.ZSEdge.F64Codec
      ] do
    short = codec |> Module.split() |> List.last()

    property "P3: #{short} — encoded size == header + block_length" do
      codec = unquote(codec)
      schema = codec.__schema__()
      expected = unquote(@header_size) + schema.block_length

      check all(attrs <- GridCodec.Generators.for_codec(codec)) do
        {:ok, struct} = codec.new(attrs)
        {:ok, bin} = codec.encode(struct)
        assert byte_size(bin) == expected
      end
    end
  end

  # ═══════════════════════════════════════════════════════════════════════
  # P6+: Garbage Rejection (strengthened)
  #
  # 1. decode/1 never crashes on arbitrary bytes (liveness)
  # 2. A valid binary with a mangled template_id is always rejected
  # ═══════════════════════════════════════════════════════════════════════

  for codec <- [
        GridCodec.ZSEdge.EnumCodec,
        GridCodec.ZSEdge.IntegerCodec,
        GridCodec.ZSEdge.F64Codec
      ] do
    short = codec |> Module.split() |> List.last()

    property "P6+: #{short} — decode never crashes on random bytes" do
      codec = unquote(codec)

      check all(garbage <- StreamData.binary(min_length: 0, max_length: 256)) do
        result = codec.decode(garbage)
        assert match?({:ok, _}, result) or match?({:error, _}, result)
      end
    end
  end

  property "P6+: wrong template_id is always rejected" do
    check all(attrs <- GridCodec.Generators.for_codec(GridCodec.ZSEdge.IntegerCodec)) do
      {:ok, struct} = GridCodec.ZSEdge.IntegerCodec.new(attrs)
      {:ok, bin} = GridCodec.ZSEdge.IntegerCodec.encode(struct)

      <<pre::binary-size(2), _tid::little-16, post::binary>> = bin
      mangled = <<pre::binary, 9999::little-16, post::binary>>

      assert {:error, _} = GridCodec.ZSEdge.IntegerCodec.decode(mangled)
    end
  end

  # ═══════════════════════════════════════════════════════════════════════
  # P7: Type Isolation
  #
  # a) The header of every encoded binary contains the correct metadata
  # b) A binary encoded by codec A is rejected by codec B
  # c) All codecs in the test universe have distinct template_ids
  #
  # Together these prove that no two types can be confused at the wire level.
  # ═══════════════════════════════════════════════════════════════════════

  for codec <- [
        GridCodec.ZSEdge.EnumCodec,
        GridCodec.ZSEdge.BitsetCodec,
        GridCodec.ZSEdge.CharCodec,
        GridCodec.ZSEdge.IntegerCodec,
        GridCodec.ZSEdge.F64Codec
      ] do
    short = codec |> Module.split() |> List.last()

    property "P7a: #{short} — header template_id and schema_id are correct" do
      codec = unquote(codec)
      schema = codec.__schema__()

      check all(attrs <- GridCodec.Generators.for_codec(codec)) do
        {:ok, struct} = codec.new(attrs)
        {:ok, bin} = codec.encode(struct)
        {:ok, header, _rest} = GridCodec.Header.decode(bin)

        assert header.template_id == schema.template_id
        assert header.schema_id == schema.schema_id
        assert header.block_length == schema.block_length
        assert header.version == schema.version
      end
    end
  end

  property "P7b: IntegerCodec binary is rejected by EnumCodec" do
    check all(attrs <- GridCodec.Generators.for_codec(GridCodec.ZSEdge.IntegerCodec)) do
      {:ok, struct} = GridCodec.ZSEdge.IntegerCodec.new(attrs)
      {:ok, bin} = GridCodec.ZSEdge.IntegerCodec.encode(struct)
      assert {:error, _} = GridCodec.ZSEdge.EnumCodec.decode(bin)
    end
  end

  property "P7b: EnumCodec binary is rejected by F64Codec" do
    check all(attrs <- GridCodec.Generators.for_codec(GridCodec.ZSEdge.EnumCodec)) do
      {:ok, struct} = GridCodec.ZSEdge.EnumCodec.new(attrs)
      {:ok, bin} = GridCodec.ZSEdge.EnumCodec.encode(struct)
      assert {:error, _} = GridCodec.ZSEdge.F64Codec.decode(bin)
    end
  end

  property "P7b: BitsetCodec binary is rejected by CharCodec" do
    check all(attrs <- GridCodec.Generators.for_codec(GridCodec.ZSEdge.BitsetCodec)) do
      {:ok, struct} = GridCodec.ZSEdge.BitsetCodec.new(attrs)
      {:ok, bin} = GridCodec.ZSEdge.BitsetCodec.encode(struct)
      assert {:error, _} = GridCodec.ZSEdge.CharCodec.decode(bin)
    end
  end

  test "P7c: all generatable codecs have distinct template_ids" do
    ids = Enum.map(@generatable_codecs, & &1.__schema__().template_id)
    assert length(ids) == length(Enum.uniq(ids))
  end

  # ═══════════════════════════════════════════════════════════════════════
  # P8: Formatter/Parser Agreement
  #
  # For a compiled codec: format it to .grid text, parse it back, and verify
  # the parsed schema matches the original __schema__/0 metadata.
  #
  # This proves: parse(format(schema)) ≈ schema
  # (modulo representation: compiled schema uses atoms, parsed uses maps)
  # ═══════════════════════════════════════════════════════════════════════

  describe "P8: formatter/parser roundtrip" do
    for codec <- [
          GridCodec.ZSEdge.IntegerCodec,
          GridCodec.ZSEdge.F64Codec
        ] do
      short = codec |> Module.split() |> List.last()

      test "P8: #{short} — format then parse recovers fields and template_id" do
        codec = unquote(codec)
        schema = codec.__schema__()

        grid_text =
          GridCodec.Schema.Formatter.format(
            "TestSchema",
            schema.schema_id,
            schema.version,
            [{codec, schema}]
          )

        assert {:ok, parsed} = GridCodec.Schema.Parser.parse(grid_text)

        struct_name = GridCodec.Schema.Formatter.struct_name(schema) |> String.to_atom()
        parsed_struct = parsed.structs[struct_name]
        assert parsed_struct, "struct #{struct_name} not found in parsed schema"

        assert parsed_struct.template_id == schema.template_id

        original_names = Enum.map(schema.fields, fn {name, _t, _o} -> name end)
        parsed_names = Enum.map(parsed_struct.fields, fn f -> f.name end)
        assert parsed_names == original_names
      end
    end

    test "P8: EnumCodec — enum type survives format/parse roundtrip" do
      codec = GridCodec.ZSEdge.EnumCodec
      schema = codec.__schema__()

      grid_text =
        GridCodec.Schema.Formatter.format(
          "TestSchema",
          schema.schema_id,
          schema.version,
          [{codec, schema}]
        )

      assert {:ok, parsed} = GridCodec.Schema.Parser.parse(grid_text)

      struct_name = GridCodec.Schema.Formatter.struct_name(schema) |> String.to_atom()
      parsed_struct = parsed.structs[struct_name]
      assert parsed_struct

      assert parsed_struct.template_id == schema.template_id
      assert length(parsed_struct.fields) == length(schema.fields)

      assert map_size(parsed.enums) >= 1,
             "formatter should emit enum definitions that the parser recovers"
    end

    test "P8: format is parseable (multi-codec schema)" do
      codecs =
        [GridCodec.ZSEdge.IntegerCodec, GridCodec.ZSEdge.F64Codec]
        |> Enum.map(fn c -> {c, c.__schema__()} end)

      grid_text =
        GridCodec.Schema.Formatter.format("Multi", 0, 1, codecs)

      assert {:ok, parsed} = GridCodec.Schema.Parser.parse(grid_text)
      assert map_size(parsed.structs) == 2
    end
  end

  # ═══════════════════════════════════════════════════════════════════════
  # P9: Byte-Level Idempotence
  #
  # encode(decode(encode(x)).value) == encode(x)
  #
  # Stronger than P1+P2 combined: proves that the encode/decode cycle
  # preserves ALL information at the byte level, not just at the struct level.
  # If the encoding were lossy (e.g., truncating precision), P1 could pass
  # while P9 would fail.
  # ═══════════════════════════════════════════════════════════════════════

  for codec <- [
        GridCodec.ZSEdge.EnumCodec,
        GridCodec.ZSEdge.BitsetCodec,
        GridCodec.ZSEdge.CharCodec,
        GridCodec.ZSEdge.IntegerCodec,
        GridCodec.ZSEdge.F64Codec
      ] do
    short = codec |> Module.split() |> List.last()

    property "P9: #{short} — encode(decode(encode(x))) == encode(x)" do
      codec = unquote(codec)

      check all(attrs <- GridCodec.Generators.for_codec(codec)) do
        {:ok, struct} = codec.new(attrs)
        {:ok, bin1} = codec.encode(struct)
        {:ok, decoded} = codec.decode(bin1)
        {:ok, bin2} = codec.encode(decoded)
        assert bin1 == bin2
      end
    end
  end

  # ═══════════════════════════════════════════════════════════════════════
  # P10: Exhaustive Proofs for Finite Domains
  #
  # For domains with finitely many values, we enumerate ALL of them.
  # This is not probabilistic — it is a constructive proof by exhaustion.
  # ═══════════════════════════════════════════════════════════════════════

  describe "P10: exhaustive finite-domain proofs" do
    test "P10a: every TestEnum variant roundtrips (3 variants = 3 checks)" do
      for {variant, _val} <- GridCodec.ZSEdge.TestEnum.values() do
        {:ok, struct} = GridCodec.ZSEdge.EnumCodec.new(%{side: variant})
        {:ok, bin} = GridCodec.ZSEdge.EnumCodec.encode(struct)
        {:ok, decoded} = GridCodec.ZSEdge.EnumCodec.decode(bin)
        assert decoded.side == variant
      end
    end

    test "P10b: every TestBitset combination roundtrips (2^4 = 16 combinations)" do
      flags = [:admin, :moderator, :verified, :banned]

      for n <- 0..15 do
        active =
          flags
          |> Enum.with_index()
          |> Enum.filter(fn {_f, i} -> Bitwise.band(n, Bitwise.bsl(1, i)) != 0 end)
          |> Enum.map(fn {f, _i} -> f end)
          |> MapSet.new()

        {:ok, struct} = GridCodec.ZSEdge.BitsetCodec.new(%{flags: active})
        {:ok, bin} = GridCodec.ZSEdge.BitsetCodec.encode(struct)
        {:ok, decoded} = GridCodec.ZSEdge.BitsetCodec.decode(bin)
        assert decoded.flags == active, "bitset #{n} failed"
      end
    end

    test "P10c: null sentinels encode to nil on decode" do
      # Null sentinel values should roundtrip as nil.
      # u8=255 is null, i8=-128 is null, etc.
      sentinel_cases = [
        {%{u8: nil, u32: 0, i8: 0, i64: 0}, :u8},
        {%{u8: 0, u32: nil, i8: 0, i64: 0}, :u32},
        {%{u8: 0, u32: 0, i8: nil, i64: 0}, :i8},
        {%{u8: 0, u32: 0, i8: 0, i64: nil}, :i64}
      ]

      for {attrs, nil_field} <- sentinel_cases do
        {:ok, struct} = GridCodec.ZSEdge.IntegerCodec.new(attrs)
        {:ok, bin} = GridCodec.ZSEdge.IntegerCodec.encode(struct)
        {:ok, decoded} = GridCodec.ZSEdge.IntegerCodec.decode(bin)
        assert Map.get(decoded, nil_field) == nil, "nil for #{nil_field} should roundtrip"
      end
    end

    test "P10d: enum nil sentinel roundtrips" do
      {:ok, struct} = GridCodec.ZSEdge.EnumCodec.new(%{side: nil})
      {:ok, bin} = GridCodec.ZSEdge.EnumCodec.encode(struct)
      {:ok, decoded} = GridCodec.ZSEdge.EnumCodec.decode(bin)
      assert decoded.side == nil
    end

    test "P10e: integer boundary values roundtrip (excluding null sentinels)" do
      boundaries = %{
        u8: [0, 1, 253, 254],
        u32: [0, 1, 4_294_967_293, 4_294_967_294],
        i8: [-127, -1, 0, 1, 127],
        i64: [-9_223_372_036_854_775_807, -1, 0, 1, 9_223_372_036_854_775_807]
      }

      for {field, values} <- boundaries, val <- values do
        base = %{u8: 0, u32: 0, i8: 0, i64: 0}
        attrs = Map.put(base, field, val)
        {:ok, struct} = GridCodec.ZSEdge.IntegerCodec.new(attrs)
        {:ok, bin} = GridCodec.ZSEdge.IntegerCodec.encode(struct)
        {:ok, decoded} = GridCodec.ZSEdge.IntegerCodec.decode(bin)
        assert Map.get(decoded, field) == val, "#{field}=#{val} failed roundtrip"
      end
    end
  end

  # ═══════════════════════════════════════════════════════════════════════
  # P11: Parser EBNF Compliance
  #
  # The parser accepts all well-formed .grid input and rejects all
  # inputs that violate the EBNF grammar.
  # ═══════════════════════════════════════════════════════════════════════

  describe "P11: parser EBNF compliance" do
    @valid_grid """
    @syntax 1

    schema Test {
      id: 1
      version: 1
    }

    enum Side : u8 {
      buy = 1
      sell = 2
    }

    struct Order (template_id: 1001) {
      id: uuid_string
      price: u64
      side: Side
    }
    """

    test "P11a: valid .grid parses successfully" do
      assert {:ok, schema} = GridCodec.Schema.Parser.parse(@valid_grid)
      assert schema.syntax == 1
      assert map_size(schema.structs) == 1
      assert map_size(schema.enums) == 1
    end

    test "P11b: unsupported @syntax version is rejected" do
      bad = String.replace(@valid_grid, "@syntax 1", "@syntax 99")
      assert {:error, {:unsupported_syntax, 99, _}} = GridCodec.Schema.Parser.parse(bad)
    end

    test "P11c: unknown directive is rejected" do
      bad = String.replace(@valid_grid, "@syntax 1", "@syntax 1\n@encoding utf8")
      assert {:error, {:unknown_directive, "encoding"}} = GridCodec.Schema.Parser.parse(bad)
    end

    test "P11d: ? in middle of identifier is rejected" do
      bad = """
      struct Order (template_id: 1) {
        na?me: u64
      }
      """

      assert {:error, {:invalid_identifier, "na?me"}} = GridCodec.Schema.Parser.parse(bad)
    end

    test "P11e: empty any_of is rejected" do
      bad = """
      struct Order (template_id: 1) {
        id: u64
        batch commands {
          any_of: []
          strategy: padded_union
        }
      }
      """

      assert {:error, {:empty_any_of}} = GridCodec.Schema.Parser.parse(bad)
    end

    test "P11f: legacy message keyword is rejected" do
      bad = """
      message Order (1001) {
        id: u64
      }
      """

      assert {:error, {:unexpected_token, {:word, "message"}}} =
               GridCodec.Schema.Parser.parse(bad)
    end

    test "P11g: trailing ? marks field optional and strips from name" do
      good = """
      struct Order (template_id: 1) {
        filled?: bool
      }
      """

      assert {:ok, schema} = GridCodec.Schema.Parser.parse(good)
      [field] = schema.structs[:Order].fields
      assert field.name == :filled
      assert field.optional == true
    end
  end
end
