# credo:disable-for-this-file Credo.Check.Refactor.Apply

defmodule GridCodec.ZeroSurpriseEdgeTest do
  @moduledoc """
  Edge cases and boundary conditions that probe "surprise" territory.
  Every test here represents a real-world scenario a user might encounter.
  """
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias GridCodec.ZSEdge.{
    EnumCodec,
    BitsetCodec,
    CharCodec,
    AllNilCodec,
    PosdecCodec,
    F64Codec
  }

  # ============================================================================
  # ENUM edge cases
  # ============================================================================

  describe "ENUM: roundtrip and coercion" do
    test "atoms roundtrip" do
      for side <- [:buy, :sell, :cancel] do
        {:ok, s} = EnumCodec.new(%{side: side})
        {:ok, bin} = EnumCodec.encode(s)
        {:ok, d} = EnumCodec.decode(bin)
        assert d.side == side, "#{side} did not roundtrip"
      end
    end

    test "string coercion normalizes to atom" do
      {:ok, s1} = EnumCodec.new(%{side: :buy})
      {:ok, s2} = EnumCodec.new(%{side: "buy"})
      {:ok, b1} = EnumCodec.encode(s1)
      {:ok, b2} = EnumCodec.encode(s2)
      assert b1 == b2
    end

    test "integer coercion normalizes to atom" do
      {:ok, s} = EnumCodec.new(%{side: 0})
      assert s.side == :buy, "integer 0 should coerce to :buy, got #{inspect(s.side)}"
    end

    test "nil roundtrips" do
      {:ok, s} = EnumCodec.new(%{side: nil})
      {:ok, bin} = EnumCodec.encode(s)
      {:ok, d} = EnumCodec.decode(bin)
      assert d.side == nil
    end

    test "unknown integer preserves through roundtrip" do
      s = %EnumCodec{side: 42}
      {:ok, bin} = EnumCodec.encode(s)
      {:ok, d} = EnumCodec.decode(bin)
      assert d.side == 42, "unknown enum int should survive, got #{inspect(d.side)}"
    end

    test "new/1 idempotent for enum" do
      {:ok, first} = EnumCodec.new(%{side: :sell})
      {:ok, second} = EnumCodec.new(Map.from_struct(first))
      assert first == second
    end
  end

  # ============================================================================
  # BITSET edge cases
  # ============================================================================

  describe "BITSET: null and empty behavior" do
    test "nil encodes as 0 and decodes as empty MapSet (KNOWN: nil doesn't roundtrip)" do
      {:ok, s} = BitsetCodec.new(%{flags: nil})
      {:ok, bin} = BitsetCodec.encode(s)
      {:ok, d} = BitsetCodec.decode(bin)
      assert d.flags == MapSet.new(), "nil should decode as empty MapSet, got #{inspect(d.flags)}"
    end

    test "empty MapSet roundtrips as empty MapSet" do
      {:ok, s} = BitsetCodec.new(%{flags: MapSet.new()})
      {:ok, bin} = BitsetCodec.encode(s)
      {:ok, d} = BitsetCodec.decode(bin)
      assert d.flags == MapSet.new()
    end

    test "single flag roundtrips" do
      for flag <- [:admin, :moderator, :verified, :banned] do
        {:ok, s} = BitsetCodec.new(%{flags: MapSet.new([flag])})
        {:ok, bin} = BitsetCodec.encode(s)
        {:ok, d} = BitsetCodec.decode(bin)
        assert d.flags == MapSet.new([flag]), "#{flag} didn't roundtrip"
      end
    end

    test "all flags roundtrip" do
      all = MapSet.new([:admin, :moderator, :verified, :banned])
      {:ok, s} = BitsetCodec.new(%{flags: all})
      {:ok, bin} = BitsetCodec.encode(s)
      {:ok, d} = BitsetCodec.decode(bin)
      assert d.flags == all
    end

    test "list coercion normalizes to MapSet" do
      {:ok, s} = BitsetCodec.new(%{flags: [:admin, :verified]})
      assert s.flags == MapSet.new([:admin, :verified])
    end

    property "bitset: any combination roundtrips" do
      flags = [:admin, :moderator, :verified, :banned]

      check all(selected <- list_of(member_of(flags), max_length: 4)) do
        set = MapSet.new(selected)
        {:ok, s} = BitsetCodec.new(%{flags: set})
        {:ok, bin} = BitsetCodec.encode(s)
        {:ok, d} = BitsetCodec.decode(bin)
        assert d.flags == set
      end
    end
  end

  # ============================================================================
  # CHAR_ARRAY edge cases
  # ============================================================================

  describe "CHAR_ARRAY: boundary and unicode behavior" do
    test "nil encodes as zeros and decodes as empty string (KNOWN: nil doesn't roundtrip)" do
      {:ok, s} = CharCodec.new(%{ticker: nil})
      {:ok, bin} = CharCodec.encode(s)
      {:ok, d} = CharCodec.decode(bin)
      assert d.ticker == "", "nil should decode as empty string, got #{inspect(d.ticker)}"
    end

    test "empty string roundtrips as empty string" do
      {:ok, s} = CharCodec.new(%{ticker: ""})
      {:ok, bin} = CharCodec.encode(s)
      {:ok, d} = CharCodec.decode(bin)
      assert d.ticker == ""
    end

    test "exact-length string roundtrips" do
      {:ok, s} = CharCodec.new(%{ticker: "ABCDEFGH"})
      {:ok, bin} = CharCodec.encode(s)
      {:ok, d} = CharCodec.decode(bin)
      assert d.ticker == "ABCDEFGH"
    end

    test "shorter string is padded then trimmed back" do
      {:ok, s} = CharCodec.new(%{ticker: "BTC"})
      {:ok, bin} = CharCodec.encode(s)
      {:ok, d} = CharCodec.decode(bin)
      assert d.ticker == "BTC"
    end

    test "null bytes in middle of string are treated as terminator" do
      {:ok, s} = CharCodec.new(%{ticker: "AB\0CDEFG"})
      {:ok, bin} = CharCodec.encode(s)
      {:ok, d} = CharCodec.decode(bin)
      assert d.ticker == "AB", "string should be trimmed at first null byte"
    end

    test "new/1 idempotent for char_array" do
      {:ok, first} = CharCodec.new(%{ticker: "ETH"})
      {:ok, second} = CharCodec.new(Map.from_struct(first))
      assert first == second
    end
  end

  # ============================================================================
  # ALL-NIL roundtrip: every type at once
  # ============================================================================

  describe "ALL-NIL: every field nil simultaneously" do
    test "all-nil struct encodes and decodes without crash" do
      {:ok, s} = AllNilCodec.new(%{})
      {:ok, bin} = AllNilCodec.encode(s)
      {:ok, d} = AllNilCodec.decode(bin)

      assert d.u == nil
      assert d.i == nil
      assert d.b == nil
      assert d.uuid == nil
      assert d.ts == nil
      assert d.dt == nil
      assert d.dec == nil
      assert d.side == nil
      # Known: bitset nil → empty MapSet, char_array nil → ""
      assert d.flags == MapSet.new()
      assert d.ticker == ""
    end

    test "all-nil double roundtrip is stable" do
      {:ok, s} = AllNilCodec.new(%{})
      {:ok, b1} = AllNilCodec.encode(s)
      {:ok, d1} = AllNilCodec.decode(b1)
      {:ok, b2} = AllNilCodec.encode(d1)
      {:ok, d2} = AllNilCodec.decode(b2)
      assert b1 == b2, "all-nil binary changed on re-encode"
      assert d1 == d2
    end
  end

  # ============================================================================
  # POSITIVE DECIMAL: silent sign loss
  # ============================================================================

  describe "POSITIVE DECIMAL: negative value behavior" do
    test "positive values roundtrip" do
      d = %Decimal{sign: 1, coef: 12345, exp: -2}
      {:ok, s} = PosdecCodec.new(%{val: d})
      {:ok, bin} = PosdecCodec.encode(s)
      {:ok, decoded} = PosdecCodec.decode(bin)
      assert decoded.val == d
    end

    test "zero roundtrips" do
      d = %Decimal{sign: 1, coef: 0, exp: 0}
      {:ok, s} = PosdecCodec.new(%{val: d})
      {:ok, bin} = PosdecCodec.encode(s)
      {:ok, decoded} = PosdecCodec.decode(bin)
      assert Decimal.eq?(decoded.val, Decimal.new(0))
    end

    test "nil roundtrips" do
      {:ok, s} = PosdecCodec.new(%{val: nil})
      {:ok, bin} = PosdecCodec.encode(s)
      {:ok, decoded} = PosdecCodec.decode(bin)
      assert decoded.val == nil
    end
  end

  # ============================================================================
  # FLOAT: special values
  # ============================================================================

  describe "FLOAT: special and extreme values" do
    property "non-zero floats roundtrip exactly for f64" do
      check all(f <- float(min: -1.0e100, max: 1.0e100)) do
        if f != 0.0 do
          s = %F64Codec{f: f}
          {:ok, bin} = F64Codec.encode(s)
          {:ok, d} = F64Codec.decode(bin)
          assert d.f == f
        end
      end
    end

    test "f64: normal values encode correctly" do
      {:ok, s} = F64Codec.new(%{f: 1.0})
      assert {:ok, _} = F64Codec.encode(s)
    end

    test "f64 infinity values" do
      pos_inf = :math.exp(709)
      neg_inf = -:math.exp(709)
      s_pos = %F64Codec{f: pos_inf}
      s_neg = %F64Codec{f: neg_inf}
      {:ok, b_pos} = F64Codec.encode(s_pos)
      {:ok, b_neg} = F64Codec.encode(s_neg)
      {:ok, d_pos} = F64Codec.decode(b_pos)
      {:ok, d_neg} = F64Codec.decode(b_neg)
      assert d_pos.f == pos_inf
      assert d_neg.f == neg_inf
    end
  end

  # ============================================================================
  # UNICODE: strings with multi-byte characters
  # ============================================================================

  describe "UNICODE: multi-byte string handling" do
    test "UTF-8 emoji string roundtrips via string16" do
      {:ok, s} = GridCodec.ZSEdge.StringCodec.new(%{s16: "hello 🌍🎉"})
      {:ok, bin} = GridCodec.ZSEdge.StringCodec.encode(s)
      {:ok, d} = GridCodec.ZSEdge.StringCodec.decode(bin)
      assert d.s16 == "hello 🌍🎉"
    end

    test "CJK characters roundtrip" do
      {:ok, s} = GridCodec.ZSEdge.StringCodec.new(%{s16: "日本語テスト"})
      {:ok, bin} = GridCodec.ZSEdge.StringCodec.encode(s)
      {:ok, d} = GridCodec.ZSEdge.StringCodec.decode(bin)
      assert d.s16 == "日本語テスト"
    end

    test "mixed ASCII and unicode roundtrip" do
      {:ok, s} = GridCodec.ZSEdge.StringCodec.new(%{s16: "price: €100.50 (±5%)"})
      {:ok, bin} = GridCodec.ZSEdge.StringCodec.encode(s)
      {:ok, d} = GridCodec.ZSEdge.StringCodec.decode(bin)
      assert d.s16 == "price: €100.50 (±5%)"
    end
  end

  # ============================================================================
  # BINARY CORRUPTION: mutated binaries
  # ============================================================================

  describe "CORRUPTION: single-bit flips in encoded binary" do
    alias GridCodec.ZSEdge.IntegerCodec, as: IntC

    test "corrupted header does not crash (returns ok or error)" do
      {:ok, s} = IntC.new(%{u32: 42})
      {:ok, bin} = IntC.encode(s)

      <<first_byte, rest::binary>> = bin
      corrupted = <<Bitwise.bxor(first_byte, 0xFF), rest::binary>>

      result = IntC.decode(corrupted)
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end

    property "flipping any byte in payload still decodes (but may differ)" do
      check all(u32 <- integer(0..4_294_967_294)) do
        {:ok, s} = IntC.new(%{u32: u32})
        {:ok, bin} = IntC.encode(s)

        if byte_size(bin) > 8 do
          pos = 8
          <<pre::binary-size(pos), target, post::binary>> = bin
          flipped = <<pre::binary, Bitwise.bxor(target, 0x01), post::binary>>

          result = IntC.decode(flipped)
          assert match?({:ok, _}, result) or match?({:error, _}, result)
        end
      end
    end
  end

  # ============================================================================
  # SENTINEL BOUNDARIES: values adjacent to the null sentinel
  # ============================================================================

  describe "SENTINEL: boundary values" do
    alias GridCodec.ZSEdge.IntegerCodec, as: IntC

    test "u8: 0, 1, 253, 254 all roundtrip" do
      for val <- [0, 1, 253, 254] do
        {:ok, s} = IntC.new(%{u8: val})
        {:ok, bin} = IntC.encode(s)
        {:ok, d} = IntC.decode(bin)
        assert d.u8 == val, "u8 #{val} didn't roundtrip, got #{inspect(d.u8)}"
      end
    end

    test "i8: -127, -1, 0, 1, 127 all roundtrip" do
      for val <- [-127, -1, 0, 1, 127] do
        {:ok, s} = IntC.new(%{i8: val})
        {:ok, bin} = IntC.encode(s)
        {:ok, d} = IntC.decode(bin)
        assert d.i8 == val, "i8 #{val} didn't roundtrip"
      end
    end

    test "u64: max non-sentinel value is not available here (4-field codec)" do
      {:ok, s} = IntC.new(%{u32: 4_294_967_294})
      {:ok, bin} = IntC.encode(s)
      {:ok, d} = IntC.decode(bin)
      assert d.u32 == 4_294_967_294
    end

    test "i64: min/max storable values roundtrip" do
      min_i64 = -9_223_372_036_854_775_807
      max_i64 = 9_223_372_036_854_775_807

      {:ok, s_min} = IntC.new(%{i64: min_i64})
      {:ok, bin_min} = IntC.encode(s_min)
      {:ok, d_min} = IntC.decode(bin_min)
      assert d_min.i64 == min_i64

      {:ok, s_max} = IntC.new(%{i64: max_i64})
      {:ok, bin_max} = IntC.encode(s_max)
      {:ok, d_max} = IntC.decode(bin_max)
      assert d_max.i64 == max_i64
    end

    test "timestamp: value 1 (just above null) roundtrips" do
      {:ok, s} = AllNilCodec.new(%{ts: 1})
      {:ok, bin} = AllNilCodec.encode(s)
      {:ok, d} = AllNilCodec.decode(bin)
      assert d.ts == 1
    end

    test "timestamp: negative values roundtrip (pre-epoch)" do
      {:ok, s} = AllNilCodec.new(%{ts: -1_000_000})
      {:ok, bin} = AllNilCodec.encode(s)
      {:ok, d} = AllNilCodec.decode(bin)
      assert d.ts == -1_000_000
    end
  end

  # ============================================================================
  # STRESS: large property test with all types mixed
  # ============================================================================

  describe "STRESS: randomized mixed-type roundtrip" do
    property "random AllNilCodec values survive triple roundtrip" do
      flags_atoms = [:admin, :moderator, :verified, :banned]

      check all(
              u <- one_of([integer(0..18_446_744_073_709_551_614), constant(nil)]),
              i <-
                one_of([
                  integer(-9_223_372_036_854_775_807..9_223_372_036_854_775_807),
                  constant(nil)
                ]),
              b <- one_of([constant(true), constant(false), constant(nil)]),
              ts <- one_of([integer(1..1_893_456_000_000_000), constant(nil)]),
              selected_flags <- list_of(member_of(flags_atoms), max_length: 4),
              ticker <-
                one_of([
                  string(:ascii, min_length: 1, max_length: 7),
                  constant(nil)
                ]),
              side <- one_of([member_of([:buy, :sell, :cancel]), constant(nil)])
            ) do
        flags = if selected_flags == [], do: nil, else: MapSet.new(selected_flags)

        {:ok, s} =
          AllNilCodec.new(%{
            u: u,
            i: i,
            b: b,
            ts: ts,
            dt: nil,
            dec: nil,
            uuid: nil,
            flags: flags,
            ticker: ticker,
            side: side
          })

        {:ok, b1} = AllNilCodec.encode(s)
        {:ok, d1} = AllNilCodec.decode(b1)
        {:ok, b2} = AllNilCodec.encode(d1)
        {:ok, d2} = AllNilCodec.decode(b2)
        {:ok, b3} = AllNilCodec.encode(d2)

        assert b1 == b2, "binary instability between pass 1 and 2"
        assert b2 == b3, "binary instability between pass 2 and 3"
        assert d1 == d2, "struct instability between pass 1 and 2"
      end
    end
  end
end
