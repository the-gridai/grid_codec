defmodule GridCodec.Types.CompositeTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias GridCodec.Types.{Decimal, TimestampMicros, TimestampNanos}

  # ============================================================================
  # Decimal Type Tests
  # ============================================================================

  describe "Decimal type" do
    test "size is 9 bytes" do
      assert Decimal.size() == 9
    end

    test "alignment is 8" do
      assert Decimal.alignment() == 8
    end

    test "from_decimal converts Decimal struct" do
      d = Elixir.Decimal.new("123.45")
      {mantissa, exp} = Decimal.from_decimal(d)

      assert mantissa == 12_345
      assert exp == -2
    end

    test "to_decimal converts back" do
      d = Decimal.to_decimal(12_345, -2)

      assert d.sign == 1
      assert d.coef == 12_345
      assert d.exp == -2
    end

    test "roundtrip with Decimal struct" do
      original = Elixir.Decimal.new("999.999")
      {m, e} = Decimal.from_decimal(original)
      result = Decimal.to_decimal(m, e)

      assert Elixir.Decimal.eq?(original, result)
    end

    test "handles negative decimals" do
      d = Elixir.Decimal.new("-42.5")
      {mantissa, exp} = Decimal.from_decimal(d)

      assert mantissa == -425
      assert exp == -1

      result = Decimal.to_decimal(mantissa, exp)
      assert Elixir.Decimal.eq?(d, result)
    end

    test "from_float converts with precision" do
      {mantissa, exp} = Decimal.from_float(123.456)

      # Default precision is -8
      assert exp == -8
      assert mantissa == 12_345_600_000
    end

    test "to_float converts back" do
      f = Decimal.to_float(12_345, -2)
      assert_in_delta f, 123.45, 0.001
    end
  end

  describe "Decimal in codec" do
    defmodule PriceCodec do
      use GridCodec.Struct

      defcodec do
        field :price, :decimal
        field :quantity, :decimal
      end
    end

    test "encode/decode roundtrip with Decimal" do
      price = Elixir.Decimal.new("99.99")
      qty = Elixir.Decimal.new("100")

      data = %PriceCodec{price: price, quantity: qty}
      binary = PriceCodec.encode(data)

      # header (8) + 9 + 9 = 26
      assert byte_size(binary) == 26

      {:ok, decoded} = PriceCodec.decode(binary)

      assert Elixir.Decimal.eq?(decoded.price, price)
      assert Elixir.Decimal.eq?(decoded.quantity, qty)
    end

    test "encode/decode with tuple format" do
      data = %PriceCodec{price: {9999, -2}, quantity: {100, 0}}
      binary = PriceCodec.encode(data)

      {:ok, decoded} = PriceCodec.decode(binary)

      assert Elixir.Decimal.eq?(decoded.price, Elixir.Decimal.new("99.99"))
      assert Elixir.Decimal.eq?(decoded.quantity, Elixir.Decimal.new("100"))
    end

    test "encode/decode with nil" do
      data = %PriceCodec{price: {100, 0}, quantity: nil}
      binary = PriceCodec.encode(data)

      {:ok, decoded} = PriceCodec.decode(binary)

      assert decoded.quantity == nil
    end

    test "zero-copy access via get macro" do
      require PriceCodec

      data = %PriceCodec{price: {12345, -2}, quantity: {500, 0}}
      binary = PriceCodec.encode(data)

      price = PriceCodec.get(binary, :price)
      assert Elixir.Decimal.eq?(price, Elixir.Decimal.new("123.45"))
    end
  end

  # ============================================================================
  # TimestampMicros Tests
  # ============================================================================

  describe "TimestampMicros type" do
    test "size is 8 bytes" do
      assert TimestampMicros.size() == 8
    end

    test "alignment is 8" do
      assert TimestampMicros.alignment() == 8
    end

    test "to_datetime converts microseconds" do
      # 2024-01-01 00:00:00 UTC
      us = 1_704_067_200_000_000
      dt = TimestampMicros.to_datetime(us)

      assert dt.year == 2024
      assert dt.month == 1
      assert dt.day == 1
    end

    test "from_datetime converts DateTime" do
      dt = ~U[2024-01-01 12:30:45.123456Z]
      us = TimestampMicros.from_datetime(dt)

      assert us == DateTime.to_unix(dt, :microsecond)
    end

    test "nil returns nil" do
      assert TimestampMicros.to_datetime(nil) == nil
      assert TimestampMicros.to_datetime(0) == nil
      assert TimestampMicros.from_datetime(nil) == 0
    end
  end

  describe "TimestampMicros in codec" do
    defmodule EventCodecUS do
      use GridCodec.Struct

      defcodec do
        field :id, :u64
        field :created_at, :timestamp_us
      end
    end

    test "encode/decode with DateTime" do
      now = DateTime.utc_now()
      data = %EventCodecUS{id: 123, created_at: now}

      binary = EventCodecUS.encode(data)
      {:ok, decoded} = EventCodecUS.decode(binary)

      assert decoded.id == 123
      # Decode returns integer, use helper to convert
      dt = TimestampMicros.to_datetime(decoded.created_at)
      assert DateTime.diff(dt, now, :microsecond) == 0
    end

    test "encode/decode with integer microseconds" do
      us = System.system_time(:microsecond)
      data = %EventCodecUS{id: 456, created_at: us}

      binary = EventCodecUS.encode(data)
      {:ok, decoded} = EventCodecUS.decode(binary)

      assert decoded.created_at == us
    end

    test "encode/decode nil" do
      data = %EventCodecUS{id: 789, created_at: nil}

      binary = EventCodecUS.encode(data)
      {:ok, decoded} = EventCodecUS.decode(binary)

      assert decoded.created_at == nil
    end

    test "zero-copy access via get macro" do
      require EventCodecUS

      us = 1_704_067_200_000_000
      data = %EventCodecUS{id: 100, created_at: us}

      binary = EventCodecUS.encode(data)

      assert EventCodecUS.get(binary, :created_at) == us
    end
  end

  # ============================================================================
  # TimestampNanos Tests
  # ============================================================================

  describe "TimestampNanos type" do
    test "size is 8 bytes" do
      assert TimestampNanos.size() == 8
    end

    test "to_datetime converts nanoseconds" do
      # Same datetime as above but in nanos
      ns = 1_704_067_200_000_000_000
      dt = TimestampNanos.to_datetime(ns)

      assert dt.year == 2024
      assert dt.month == 1
      assert dt.day == 1
    end

    test "from_datetime converts DateTime" do
      dt = ~U[2024-01-01 12:30:45.123456Z]
      ns = TimestampNanos.from_datetime(dt)

      # DateTime has microsecond precision, so nanos will be truncated
      assert ns == DateTime.to_unix(dt, :nanosecond)
    end
  end

  describe "TimestampNanos in codec" do
    defmodule EventCodecNS do
      use GridCodec.Struct

      defcodec do
        field :event_time, :timestamp_ns
        field :sequence, :u64
      end
    end

    test "encode/decode with System.system_time" do
      ns = System.system_time(:nanosecond)
      data = %EventCodecNS{event_time: ns, sequence: 1}

      binary = EventCodecNS.encode(data)
      {:ok, decoded} = EventCodecNS.decode(binary)

      assert decoded.event_time == ns
      assert decoded.sequence == 1
    end

    test "encode/decode with DateTime" do
      dt = DateTime.utc_now()
      data = %EventCodecNS{event_time: dt, sequence: 2}

      binary = EventCodecNS.encode(data)
      {:ok, decoded} = EventCodecNS.decode(binary)

      # Will be in nanoseconds
      assert is_integer(decoded.event_time)
    end
  end

  # ============================================================================
  # Property Tests - Use pre-defined codecs
  # ============================================================================

  defmodule DecimalPropCodec do
    use GridCodec.Struct

    defcodec do
      field :val, :decimal
    end
  end

  defmodule TSMicrosPropCodec do
    use GridCodec.Struct

    defcodec do
      field :ts, :timestamp_us
    end
  end

  defmodule TSNanosPropCodec do
    use GridCodec.Struct

    defcodec do
      field :ts, :timestamp_ns
    end
  end

  describe "property: decimal roundtrip" do
    property "tuple format roundtrips" do
      check all(
              mantissa <- StreamData.integer(-1_000_000_000..1_000_000_000),
              exp <- StreamData.integer(-10..10),
              max_runs: 100
            ) do
        original = {mantissa, exp}

        binary = DecimalPropCodec.encode(%DecimalPropCodec{val: original})
        {:ok, decoded} = DecimalPropCodec.decode(binary)

        result = Decimal.from_decimal(decoded.val)
        assert result == original
      end
    end
  end

  describe "property: timestamp roundtrip" do
    property "microsecond timestamps roundtrip" do
      check all(
              us <- StreamData.integer(1..2_000_000_000_000_000),
              max_runs: 50
            ) do
        binary = TSMicrosPropCodec.encode(%TSMicrosPropCodec{ts: us})
        {:ok, decoded} = TSMicrosPropCodec.decode(binary)

        assert decoded.ts == us
      end
    end

    property "nanosecond timestamps roundtrip" do
      check all(
              ns <- StreamData.integer(1..2_000_000_000_000_000_000),
              max_runs: 50
            ) do
        binary = TSNanosPropCodec.encode(%TSNanosPropCodec{ts: ns})
        {:ok, decoded} = TSNanosPropCodec.decode(binary)

        assert decoded.ts == ns
      end
    end
  end
end
