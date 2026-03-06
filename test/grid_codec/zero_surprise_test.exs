# credo:disable-for-this-file Credo.Check.Refactor.Apply

# Codecs defined at top level so they can be `require`d inside the test module.
defmodule GridCodec.ZS.IntegerCodec do
  use GridCodec.Struct, template_id: 5000, validate: true

  defcodec do
    field :u8, :u8
    field :u16, :u16
    field :u32, :u32
    field :u64, :u64
    field :i8, :i8
    field :i16, :i16
    field :i32, :i32
    field :i64, :i64
  end
end

defmodule GridCodec.ZS.FloatCodec do
  use GridCodec.Struct, template_id: 5001

  defcodec do
    field :f32, :f32
    field :f64, :f64
  end
end

defmodule GridCodec.ZS.StringCodec do
  use GridCodec.Struct, template_id: 5002

  defcodec do
    field :s8, :string8
    field :s16, :string16
    field :s32, :string32
  end
end

defmodule GridCodec.ZS.UUIDCodec do
  use GridCodec.Struct, template_id: 5003

  defcodec do
    field :raw, :uuid
    field :str, :uuid_string
  end
end

defmodule GridCodec.ZS.TimestampCodec do
  use GridCodec.Struct, template_id: 5004

  defcodec do
    field :ts_us, :timestamp_us
    field :ts_ns, :timestamp_ns
    field :dt_us, :datetime_us
    field :dt_ns, :datetime_ns
  end
end

defmodule GridCodec.ZS.DecimalCodec do
  use GridCodec.Struct, template_id: 5005

  defcodec do
    field :dec, :decimal
    field :pos, :positive_decimal
  end
end

defmodule GridCodec.ZS.BoolCodec do
  use GridCodec.Struct, template_id: 5006

  defcodec do
    field :flag, :bool
  end
end

defmodule GridCodec.ZS.KitchenSink do
  use GridCodec.Struct, template_id: 5010

  defcodec do
    field :id, :u64
    field :uuid, :uuid_string
    field :ts, :timestamp_us
    field :dt, :datetime_us
    field :price, :decimal
    field :active, :bool
    field :name, :string
  end
end

defmodule GridCodec.ZeroSurpriseTest do
  @moduledoc """
  Comprehensive "zero-surprise" audit of the GridCodec type system.

  Tests every invariant that a user would reasonably expect to hold.
  Each test section is named after the surprise it would catch if violated.
  Any failure here means a user would be surprised.
  """
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias GridCodec.ZS.IntegerCodec
  alias GridCodec.ZS.FloatCodec
  alias GridCodec.ZS.StringCodec
  alias GridCodec.ZS.UUIDCodec
  alias GridCodec.ZS.TimestampCodec
  alias GridCodec.ZS.DecimalCodec
  alias GridCodec.ZS.BoolCodec
  alias GridCodec.ZS.KitchenSink

  require IntegerCodec
  require UUIDCodec
  require BoolCodec
  require KitchenSink

  # ============================================================================
  # INVARIANT 1: new/1 → encode → decode identity
  #
  # If I create a struct with new/1 and round-trip it, every field should
  # be exactly equal. This is THE fundamental contract.
  # ============================================================================

  describe "INVARIANT: new/1 → encode → decode identity" do
    property "integers: new/1 roundtrip preserves every field" do
      check all(
              u8 <- one_of([integer(0..254), constant(nil)]),
              u16 <- one_of([integer(0..65534), constant(nil)]),
              u32 <- one_of([integer(0..4_294_967_294), constant(nil)]),
              u64 <- one_of([integer(0..18_446_744_073_709_551_614), constant(nil)]),
              i8 <- one_of([integer(-127..127), constant(nil)]),
              i16 <- one_of([integer(-32767..32767), constant(nil)]),
              i32 <- one_of([integer(-2_147_483_647..2_147_483_647), constant(nil)]),
              i64 <-
                one_of([
                  integer(-9_223_372_036_854_775_807..9_223_372_036_854_775_807),
                  constant(nil)
                ])
            ) do
        {:ok, via_new} =
          IntegerCodec.new(%{
            u8: u8,
            u16: u16,
            u32: u32,
            u64: u64,
            i8: i8,
            i16: i16,
            i32: i32,
            i64: i64
          })

        {:ok, bin} = IntegerCodec.encode(via_new)
        {:ok, decoded} = IntegerCodec.decode(bin)

        assert via_new.u8 == decoded.u8,
               "u8 mismatch: #{inspect(via_new.u8)} vs #{inspect(decoded.u8)}"

        assert via_new.u16 == decoded.u16
        assert via_new.u32 == decoded.u32
        assert via_new.u64 == decoded.u64
        assert via_new.i8 == decoded.i8
        assert via_new.i16 == decoded.i16
        assert via_new.i32 == decoded.i32
        assert via_new.i64 == decoded.i64
      end
    end

    property "uuid_string: new/1 roundtrip preserves identity for all input forms" do
      check all(uuid_bytes <- binary(length: 16)) do
        if uuid_bytes != <<0::128>> do
          uuid_str = GridCodec.Types.UUIDString.format_uuid(uuid_bytes)

          for input <- [uuid_str, uuid_bytes, String.replace(uuid_str, "-", "")] do
            {:ok, via_new} = UUIDCodec.new(%{str: input})

            assert is_binary(via_new.str) and byte_size(via_new.str) == 36,
                   "coerce should normalize to 36-char string, got: #{inspect(via_new.str)}"

            {:ok, bin} = UUIDCodec.encode(via_new)
            {:ok, decoded} = UUIDCodec.decode(bin)
            assert via_new.str == decoded.str
          end
        end
      end
    end

    property "timestamp: new/1 roundtrip preserves integer identity" do
      check all(
              ts <- one_of([integer(1..1_893_456_000_000_000), constant(nil)]),
              ns <- one_of([integer(1..1_893_456_000_000_000_000), constant(nil)])
            ) do
        {:ok, via_new} = TimestampCodec.new(%{ts_us: ts, ts_ns: ns, dt_us: nil, dt_ns: nil})
        {:ok, bin} = TimestampCodec.encode(via_new)
        {:ok, decoded} = TimestampCodec.decode(bin)

        assert via_new.ts_us == decoded.ts_us
        assert via_new.ts_ns == decoded.ts_ns
      end
    end

    property "datetime: new/1 roundtrip preserves DateTime identity" do
      check all(us <- integer(1_577_836_800_000_000..1_893_456_000_000_000)) do
        dt = DateTime.from_unix!(us, :microsecond)

        {:ok, via_new} = TimestampCodec.new(%{dt_us: dt, dt_ns: nil, ts_us: nil, ts_ns: nil})
        assert %DateTime{} = via_new.dt_us

        {:ok, bin} = TimestampCodec.encode(via_new)
        {:ok, decoded} = TimestampCodec.decode(bin)
        assert DateTime.compare(via_new.dt_us, decoded.dt_us) == :eq
      end
    end

    property "decimal: new/1 roundtrip preserves Decimal identity" do
      check all(
              mantissa <- integer(-1_000_000_000..1_000_000_000),
              exp <- integer(-8..8)
            ) do
        {sign, coef} = if mantissa < 0, do: {-1, -mantissa}, else: {1, mantissa}
        d = %Decimal{sign: sign, coef: coef, exp: exp}

        {:ok, via_new} = DecimalCodec.new(%{dec: d, pos: nil})
        {:ok, bin} = DecimalCodec.encode(via_new)
        {:ok, decoded} = DecimalCodec.decode(bin)
        assert via_new.dec == decoded.dec, "decimal mismatch"
      end
    end

    property "bool: new/1 roundtrip preserves identity" do
      check all(flag <- one_of([constant(true), constant(false), constant(nil)])) do
        {:ok, via_new} = BoolCodec.new(%{flag: flag})
        {:ok, bin} = BoolCodec.encode(via_new)
        {:ok, decoded} = BoolCodec.decode(bin)
        assert via_new.flag == decoded.flag
      end
    end

    property "string: new/1 roundtrip preserves non-empty strings" do
      check all(
              s <-
                one_of([
                  string(:alphanumeric, min_length: 1, max_length: 200),
                  constant(nil)
                ])
            ) do
        {:ok, via_new} = StringCodec.new(%{s16: s})
        {:ok, bin} = StringCodec.encode(via_new)
        {:ok, decoded} = StringCodec.decode(bin)
        assert via_new.s16 == decoded.s16
      end
    end
  end

  # ============================================================================
  # INVARIANT 2: new/1 idempotence
  #
  # Calling new/1 on a struct that already came from new/1 should produce
  # the exact same struct. No further normalization should happen.
  # ============================================================================

  describe "INVARIANT: new/1 idempotence" do
    property "integers: double-new is a no-op" do
      check all(val <- one_of([integer(0..254), constant(nil)])) do
        {:ok, first} = IntegerCodec.new(%{u8: val})
        {:ok, second} = IntegerCodec.new(Map.from_struct(first))
        assert first == second
      end
    end

    property "uuid_string: double-new is a no-op" do
      check all(uuid_bytes <- binary(length: 16)) do
        if uuid_bytes != <<0::128>> do
          str = GridCodec.Types.UUIDString.format_uuid(uuid_bytes)
          {:ok, first} = UUIDCodec.new(%{str: str})
          {:ok, second} = UUIDCodec.new(Map.from_struct(first))
          assert first == second
        end
      end
    end

    property "timestamp: double-new is a no-op" do
      check all(ts <- one_of([integer(1..1_893_456_000_000_000), constant(nil)])) do
        {:ok, first} = TimestampCodec.new(%{ts_us: ts, ts_ns: nil, dt_us: nil, dt_ns: nil})
        {:ok, second} = TimestampCodec.new(Map.from_struct(first))
        assert first == second
      end
    end

    property "datetime: double-new is a no-op" do
      check all(us <- integer(1_577_836_800_000_000..1_893_456_000_000_000)) do
        dt = DateTime.from_unix!(us, :microsecond)
        {:ok, first} = TimestampCodec.new(%{dt_us: dt, dt_ns: nil, ts_us: nil, ts_ns: nil})
        {:ok, second} = TimestampCodec.new(Map.from_struct(first))
        assert DateTime.compare(first.dt_us, second.dt_us) == :eq
      end
    end

    property "decimal: double-new is a no-op" do
      check all(mantissa <- integer(0..1_000_000), exp <- integer(-4..4)) do
        d = %Decimal{sign: 1, coef: mantissa, exp: exp}
        {:ok, first} = DecimalCodec.new(%{dec: d, pos: nil})
        {:ok, second} = DecimalCodec.new(Map.from_struct(first))
        assert first == second
      end
    end
  end

  # ============================================================================
  # INVARIANT 3: encode determinism
  #
  # Encoding the same struct twice must produce the exact same binary.
  # ============================================================================

  describe "INVARIANT: encode determinism" do
    property "same struct always produces same binary" do
      check all(id <- integer(0..18_446_744_073_709_551_614)) do
        {:ok, s} = KitchenSink.new(%{id: id, active: true, name: "test"})
        {:ok, bin1} = KitchenSink.encode(s)
        {:ok, bin2} = KitchenSink.encode(s)
        assert bin1 == bin2
      end
    end
  end

  # ============================================================================
  # INVARIANT 4: get/2 consistency
  #
  # get(binary, :field) must return the same value as decode(binary).field
  # ============================================================================

  describe "INVARIANT: get/2 matches decode for every field" do
    property "integer fields: get == decode" do
      check all(
              u32 <- one_of([integer(0..4_294_967_294), constant(nil)]),
              i64 <-
                one_of([
                  integer(-9_223_372_036_854_775_807..9_223_372_036_854_775_807),
                  constant(nil)
                ])
            ) do
        {:ok, s} = IntegerCodec.new(%{u32: u32, i64: i64})
        {:ok, bin} = IntegerCodec.encode(s)
        {:ok, decoded} = IntegerCodec.decode(bin)

        assert IntegerCodec.get(bin, :u32) == decoded.u32
        assert IntegerCodec.get(bin, :i64) == decoded.i64
      end
    end

    property "uuid_string: get == decode" do
      check all(uuid_bytes <- binary(length: 16)) do
        if uuid_bytes != <<0::128>> do
          str = GridCodec.Types.UUIDString.format_uuid(uuid_bytes)
          {:ok, s} = UUIDCodec.new(%{str: str})
          {:ok, bin} = UUIDCodec.encode(s)
          {:ok, decoded} = UUIDCodec.decode(bin)

          assert UUIDCodec.get(bin, :str) == decoded.str
        end
      end
    end

    property "bool: get == decode" do
      check all(flag <- one_of([constant(true), constant(false), constant(nil)])) do
        {:ok, s} = BoolCodec.new(%{flag: flag})
        {:ok, bin} = BoolCodec.encode(s)
        {:ok, decoded} = BoolCodec.decode(bin)

        assert BoolCodec.get(bin, :flag) == decoded.flag
      end
    end
  end

  # ============================================================================
  # INVARIANT 5: new_binary == new + encode
  #
  # The shortcut path should produce identical output.
  # ============================================================================

  describe "INVARIANT: new_binary == new + encode" do
    property "new_binary produces same binary as new then encode" do
      check all(
              id <- integer(0..18_446_744_073_709_551_614),
              flag <- one_of([constant(true), constant(false), constant(nil)])
            ) do
        attrs = %{id: id, active: flag, name: "test"}

        {:ok, struct} = KitchenSink.new(attrs)
        {:ok, via_encode} = KitchenSink.encode(struct)
        {:ok, via_shortcut} = KitchenSink.new_binary(attrs)

        assert via_encode == via_shortcut
      end
    end
  end

  # ============================================================================
  # INVARIANT 6: multi-pass stability
  #
  # encode → decode → encode → decode must be stable.
  # If the second pass differs from the first, something is normalizing
  # inconsistently.
  # ============================================================================

  describe "INVARIANT: multi-pass pipeline stability" do
    property "double roundtrip produces identical results" do
      check all(
              id <- integer(0..18_446_744_073_709_551_614),
              name <-
                one_of([string(:alphanumeric, min_length: 1, max_length: 50), constant(nil)])
            ) do
        {:ok, s} = KitchenSink.new(%{id: id, name: name, active: true})

        {:ok, bin1} = KitchenSink.encode(s)
        {:ok, d1} = KitchenSink.decode(bin1)
        {:ok, bin2} = KitchenSink.encode(d1)
        {:ok, d2} = KitchenSink.decode(bin2)

        assert bin1 == bin2, "binary changed on second pass"
        assert d1 == d2, "struct changed on second pass"
      end
    end

    property "integers: triple roundtrip is stable" do
      check all(
              u32 <- one_of([integer(0..4_294_967_294), constant(nil)]),
              i64 <-
                one_of([
                  integer(-9_223_372_036_854_775_807..9_223_372_036_854_775_807),
                  constant(nil)
                ])
            ) do
        {:ok, s} = IntegerCodec.new(%{u32: u32, i64: i64})

        {:ok, b1} = IntegerCodec.encode(s)
        {:ok, d1} = IntegerCodec.decode(b1)
        {:ok, b2} = IntegerCodec.encode(d1)
        {:ok, d2} = IntegerCodec.decode(b2)
        {:ok, b3} = IntegerCodec.encode(d2)

        assert b1 == b2
        assert b2 == b3
      end
    end
  end

  # ============================================================================
  # SURPRISE: null sentinel edge cases
  #
  # What happens when valid data collides with the null sentinel?
  # ============================================================================

  describe "SURPRISE: null sentinel boundaries" do
    test "u8: 254 is the max storable value (255 is null)" do
      {:ok, s} = IntegerCodec.new(%{u8: 254})
      {:ok, bin} = IntegerCodec.encode(s)
      {:ok, d} = IntegerCodec.decode(bin)
      assert d.u8 == 254
    end

    test "u8: nil roundtrips as nil" do
      {:ok, s} = IntegerCodec.new(%{u8: nil})
      {:ok, bin} = IntegerCodec.encode(s)
      {:ok, d} = IntegerCodec.decode(bin)
      assert d.u8 == nil
    end

    test "i8: -127 is the min storable value (-128 is null)" do
      {:ok, s} = IntegerCodec.new(%{i8: -127})
      {:ok, bin} = IntegerCodec.encode(s)
      {:ok, d} = IntegerCodec.decode(bin)
      assert d.i8 == -127
    end

    test "timestamp: epoch 0 is null — cannot store Unix epoch" do
      {:ok, s} = TimestampCodec.new(%{ts_us: 0, ts_ns: nil, dt_us: nil, dt_ns: nil})
      {:ok, bin} = TimestampCodec.encode(s)
      {:ok, d} = TimestampCodec.decode(bin)
      assert d.ts_us == nil, "epoch 0 should decode as nil (it's the null sentinel)"
    end

    test "datetime: epoch 0 is null" do
      {:ok, s} = TimestampCodec.new(%{dt_us: 0, dt_ns: nil, ts_us: nil, ts_ns: nil})
      {:ok, bin} = TimestampCodec.encode(s)
      {:ok, d} = TimestampCodec.decode(bin)
      assert d.dt_us == nil
    end

    test "uuid: all-zeros is null" do
      {:ok, s} = UUIDCodec.new(%{raw: <<0::128>>, str: nil})
      {:ok, bin} = UUIDCodec.encode(s)
      {:ok, d} = UUIDCodec.decode(bin)
      assert d.raw == nil
    end
  end

  # ============================================================================
  # SURPRISE: empty string vs nil
  #
  # String types use length=0 for both nil and empty string.
  # Users must know that "" does not survive roundtrip.
  # ============================================================================

  describe "SURPRISE: empty string is nil after roundtrip" do
    test "string: empty string encodes same as nil" do
      {:ok, s_nil} = StringCodec.new(%{s16: nil})
      {:ok, bin_nil} = StringCodec.encode(s_nil)

      {:ok, s_empty} = StringCodec.new(%{s16: ""})
      {:ok, bin_empty} = StringCodec.encode(s_empty)

      {:ok, d_nil} = StringCodec.decode(bin_nil)
      {:ok, d_empty} = StringCodec.decode(bin_empty)

      assert d_nil.s16 == nil
      assert d_empty.s16 == nil, "empty string should decode as nil (length-0 sentinel)"
    end
  end

  # ============================================================================
  # SURPRISE: float nil handling
  #
  # Floats are not nullable by default. Passing nil to a float field
  # and encoding should be tested.
  # ============================================================================

  describe "SURPRISE: float default values" do
    test "f64: 0.0 is a valid value and roundtrips" do
      s = %FloatCodec{f32: 0.0, f64: 0.0}
      {:ok, bin} = FloatCodec.encode(s)
      {:ok, d} = FloatCodec.decode(bin)
      assert d.f32 == 0.0
      assert d.f64 == 0.0
    end

    test "f64: negative zero roundtrips" do
      s = %FloatCodec{f32: -0.0, f64: -0.0}
      {:ok, bin} = FloatCodec.encode(s)
      {:ok, d} = FloatCodec.decode(bin)
      assert d.f64 == 0.0 or d.f64 == -0.0
    end

    test "f64: very small values roundtrip" do
      s = %FloatCodec{f32: 1.0e-30, f64: 1.0e-300}
      {:ok, bin} = FloatCodec.encode(s)
      {:ok, d} = FloatCodec.decode(bin)
      assert_in_delta d.f64, 1.0e-300, 1.0e-310
    end

    test "f64: very large values roundtrip" do
      s = %FloatCodec{f32: 1.0e30, f64: 1.0e300}
      {:ok, bin} = FloatCodec.encode(s)
      {:ok, d} = FloatCodec.decode(bin)
      assert_in_delta d.f64, 1.0e300, 1.0e290
    end
  end

  # ============================================================================
  # SURPRISE: coercion input diversity
  #
  # new/1 should accept multiple input formats and normalize them.
  # All formats should produce the same encoded binary.
  # ============================================================================

  describe "SURPRISE: all coercion paths produce same binary" do
    test "integer: string '42' and integer 42 produce same binary" do
      {:ok, s1} = IntegerCodec.new(%{u32: 42})
      {:ok, s2} = IntegerCodec.new(%{u32: "42"})
      {:ok, b1} = IntegerCodec.encode(s1)
      {:ok, b2} = IntegerCodec.encode(s2)
      assert b1 == b2
    end

    test "bool: true, 'true', and 1 all produce same binary" do
      {:ok, s1} = BoolCodec.new(%{flag: true})
      {:ok, s2} = BoolCodec.new(%{flag: "true"})
      {:ok, s3} = BoolCodec.new(%{flag: 1})
      {:ok, b1} = BoolCodec.encode(s1)
      {:ok, b2} = BoolCodec.encode(s2)
      {:ok, b3} = BoolCodec.encode(s3)
      assert b1 == b2
      assert b2 == b3
    end

    test "uuid_string: raw bytes, dash string, and hex string produce same binary" do
      raw = <<85, 14, 132, 0, 226, 155, 65, 212, 167, 22, 68, 102, 85, 68, 0, 0>>
      dash = "550e8400-e29b-41d4-a716-446655440000"
      hex = "550e8400e29b41d4a716446655440000"

      {:ok, s1} = UUIDCodec.new(%{str: raw})
      {:ok, s2} = UUIDCodec.new(%{str: dash})
      {:ok, s3} = UUIDCodec.new(%{str: hex})
      {:ok, b1} = UUIDCodec.encode(s1)
      {:ok, b2} = UUIDCodec.encode(s2)
      {:ok, b3} = UUIDCodec.encode(s3)
      assert b1 == b2
      assert b2 == b3
    end

    test "timestamp: DateTime and integer produce same binary" do
      dt = ~U[2024-06-15 12:30:00.000000Z]
      us = DateTime.to_unix(dt, :microsecond)

      {:ok, s1} = TimestampCodec.new(%{ts_us: dt, ts_ns: nil, dt_us: nil, dt_ns: nil})
      {:ok, s2} = TimestampCodec.new(%{ts_us: us, ts_ns: nil, dt_us: nil, dt_ns: nil})
      {:ok, b1} = TimestampCodec.encode(s1)
      {:ok, b2} = TimestampCodec.encode(s2)
      assert b1 == b2
    end

    test "timestamp: ISO 8601 string produces same binary as DateTime" do
      {:ok, s1} =
        TimestampCodec.new(%{ts_us: "2024-06-15T12:30:00Z", ts_ns: nil, dt_us: nil, dt_ns: nil})

      {:ok, s2} =
        TimestampCodec.new(%{
          ts_us: ~U[2024-06-15 12:30:00Z],
          ts_ns: nil,
          dt_us: nil,
          dt_ns: nil
        })

      {:ok, b1} = TimestampCodec.encode(s1)
      {:ok, b2} = TimestampCodec.encode(s2)
      assert b1 == b2
    end

    test "decimal: {m, e} tuple and %Decimal{} produce same binary" do
      {:ok, s1} = DecimalCodec.new(%{dec: {12345, -2}, pos: nil})
      {:ok, s2} = DecimalCodec.new(%{dec: Decimal.new("123.45"), pos: nil})
      {:ok, b1} = DecimalCodec.encode(s1)
      {:ok, b2} = DecimalCodec.encode(s2)
      assert b1 == b2
    end
  end

  # ============================================================================
  # SURPRISE: cross-type wire compatibility
  #
  # :datetime_us and :timestamp_us share the same wire format.
  # A binary encoded with one should be decodable by the other.
  # ============================================================================

  describe "SURPRISE: timestamp/datetime wire compatibility" do
    test "same microsecond value produces identical payload bytes" do
      us = 1_718_451_000_123_456
      dt = DateTime.from_unix!(us, :microsecond)

      {:ok, s_ts} = TimestampCodec.new(%{ts_us: us, ts_ns: nil, dt_us: nil, dt_ns: nil})
      {:ok, s_dt} = TimestampCodec.new(%{ts_us: nil, ts_ns: nil, dt_us: dt, dt_ns: nil})

      {:ok, b_ts} = TimestampCodec.encode(s_ts)
      {:ok, b_dt} = TimestampCodec.encode(s_dt)

      header = 8
      ts_field_offset = 0
      dt_field_offset = 16

      ts_bytes = binary_part(b_ts, header + ts_field_offset, 8)
      dt_bytes = binary_part(b_dt, header + dt_field_offset, 8)
      assert ts_bytes == dt_bytes
    end
  end

  # ============================================================================
  # SURPRISE: content_hash stability
  #
  # Same data must always produce the same content_hash, regardless of
  # how it was constructed.
  # ============================================================================

  describe "INVARIANT: content_hash stability" do
    property "same values always produce same hash" do
      check all(id <- integer(0..18_446_744_073_709_551_614)) do
        {:ok, s1} = KitchenSink.new(%{id: id, active: true, name: "x"})
        {:ok, s2} = KitchenSink.new(%{id: id, active: true, name: "x"})
        assert KitchenSink.content_hash(s1) == KitchenSink.content_hash(s2)
      end
    end

    test "different values produce different hashes" do
      {:ok, s1} = KitchenSink.new(%{id: 1, active: true})
      {:ok, s2} = KitchenSink.new(%{id: 2, active: true})
      assert KitchenSink.content_hash(s1) != KitchenSink.content_hash(s2)
    end
  end

  # ============================================================================
  # SURPRISE: header correctness
  #
  # Every encoded binary must have the correct header.
  # ============================================================================

  describe "INVARIANT: header correctness" do
    test "block_length in header matches actual fixed block" do
      {:ok, s} = KitchenSink.new(%{id: 42})
      {:ok, bin} = KitchenSink.encode(s)

      <<block_length::little-16, _template_id::little-16, _schema_id::little-16,
        _version::little-16, _rest::binary>> = bin

      assert block_length == KitchenSink.block_length()
    end

    test "template_id in header matches module" do
      {:ok, s} = KitchenSink.new(%{id: 42})
      {:ok, bin} = KitchenSink.encode(s)

      <<_bl::little-16, template_id::little-16, _rest::binary>> = bin
      assert template_id == KitchenSink.__template_id__()
    end
  end

  # ============================================================================
  # FUZZ: random binary decode resilience
  #
  # Random binaries should not crash decode — it should return {:error, ...}
  # or succeed gracefully. Never raise.
  # ============================================================================

  describe "FUZZ: random binary decode resilience" do
    property "random binaries never crash decode (integers)" do
      check all(bin <- binary(min_length: 0, max_length: 200)) do
        result = IntegerCodec.decode(bin)
        assert match?({:ok, _}, result) or match?({:error, _}, result)
      end
    end

    property "random binaries never crash decode (kitchen sink)" do
      check all(bin <- binary(min_length: 0, max_length: 500)) do
        result = KitchenSink.decode(bin)
        assert match?({:ok, _}, result) or match?({:error, _}, result)
      end
    end
  end

  # ============================================================================
  # SURPRISE: coercion error messages
  #
  # Invalid input to new/1 should produce clear error tuples, not crashes.
  # ============================================================================

  describe "SURPRISE: bad input to new/1 returns error, never crashes" do
    test "integer: non-numeric string returns error" do
      assert {:error, _} = IntegerCodec.new(%{u32: "not_a_number"})
    end

    test "bool: invalid string returns error" do
      assert {:error, _} = BoolCodec.new(%{flag: "maybe"})
    end

    test "uuid_string: wrong-length string returns error" do
      assert {:error, _} = UUIDCodec.new(%{str: "too-short"})
    end

    test "timestamp: invalid ISO string returns error" do
      assert {:error, _} =
               TimestampCodec.new(%{ts_us: "not-a-date", ts_ns: nil, dt_us: nil, dt_ns: nil})
    end

    test "decimal: invalid string returns error" do
      assert {:error, _} = DecimalCodec.new(%{dec: "not_decimal", pos: nil})
    end

    test "completely wrong type returns error" do
      assert {:error, _} = IntegerCodec.new(%{u32: [:list]})
    end
  end

  # ============================================================================
  # PIPELINE SIMULATION: realistic multi-step data flow
  #
  # Simulates a realistic pipeline:
  # 1. Create struct from external input (new/1)
  # 2. Encode for storage/transport
  # 3. Decode on receiving side
  # 4. Access individual fields (get/2)
  # 5. Re-encode for forwarding
  # 6. Decode again at final destination
  # All values must be identical at every stage.
  # ============================================================================

  describe "PIPELINE: multi-hop data flow simulation" do
    property "values survive a 3-hop pipeline" do
      check all(
              id <- integer(0..18_446_744_073_709_551_614),
              name <-
                one_of([string(:alphanumeric, min_length: 1, max_length: 100), constant(nil)])
            ) do
        {:ok, original} = KitchenSink.new(%{id: id, name: name, active: true})

        {:ok, hop1_bin} = KitchenSink.encode(original)
        {:ok, hop1} = KitchenSink.decode(hop1_bin)

        {:ok, hop2_bin} = KitchenSink.encode(hop1)
        {:ok, hop2} = KitchenSink.decode(hop2_bin)

        {:ok, hop3_bin} = KitchenSink.encode(hop2)
        {:ok, hop3} = KitchenSink.decode(hop3_bin)

        assert hop1_bin == hop2_bin, "binary changed between hop 1 and 2"
        assert hop2_bin == hop3_bin, "binary changed between hop 2 and 3"
        assert hop1 == hop2
        assert hop2 == hop3

        assert KitchenSink.get(hop1_bin, :id) == id
        assert hop1.name == name
      end
    end
  end
end
