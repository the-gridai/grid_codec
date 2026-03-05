defmodule GridCodec.MatchTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  # ── Test codecs ──────────────────────────────────────────────────────────

  defmodule Envelope do
    use GridCodec.Struct, template_id: 8800, schema_id: 88

    defcodec do
      field :trace_id, :uuid
      field :span_id, :u64
      field :flags, :u32
      field :message_type, :u16
    end
  end

  defmodule Span do
    use GridCodec.Struct, template_id: 8801, schema_id: 88

    defcodec do
      field :trace_id, :uuid
      field :span_id, :u64
      field :parent_span_id, :u64
      field :flags, :u32
      field :kind, :u8
      field :start_time_ns, :timestamp_ns
      field :end_time_ns, :timestamp_ns
    end
  end

  # ── Filter modules using GridCodec.Match ──────────────────────────────────

  defmodule Filters do
    use GridCodec.Match

    defmatch :sampled?, Envelope do
      where(flags == 1)
    end

    defmatch :not_sampled?, Envelope do
      where(flags == 0)
    end

    defmatch :bitwise_sampled?, Envelope do
      where(band(flags, 0x01) == 1)
    end

    defmatch :high_message_type?, Envelope do
      where(message_type > 100)
    end

    defmatch :slow_span?, Span do
      where(end_time_ns - start_time_ns > 1_000_000)
    end

    defmatch :sampled_server?, Span do
      where(band(flags, 1) == 1)
      where(kind == 3)
    end

    defmatch :extract_context, Envelope, select: [:trace_id, :span_id] do
      where(flags == 1)
    end
  end

  # ── Test data ────────────────────────────────────────────────────────────

  @trace_id :crypto.strong_rand_bytes(16)

  defp encode_envelope(flags, msg_type) do
    env =
      struct!(Envelope, trace_id: @trace_id, span_id: 42, flags: flags, message_type: msg_type)

    {:ok, bin} = Envelope.encode(env)
    bin
  end

  defp encode_span(flags, kind, start_ns, end_ns) do
    span =
      struct!(Span,
        trace_id: @trace_id,
        span_id: 1,
        parent_span_id: 2,
        flags: flags,
        kind: kind,
        start_time_ns: start_ns,
        end_time_ns: end_ns
      )

    {:ok, bin} = Span.encode(span)
    bin
  end

  # ── Tests ────────────────────────────────────────────────────────────────

  describe "simple field equality" do
    test "matches when field equals value" do
      assert Filters.sampled?(encode_envelope(1, 10))
    end

    test "rejects when field does not equal value" do
      refute Filters.sampled?(encode_envelope(0, 10))
      refute Filters.sampled?(encode_envelope(2, 10))
    end

    test "rejects non-binary input" do
      refute Filters.sampled?(:not_a_binary)
      refute Filters.sampled?(42)
      refute Filters.sampled?(nil)
    end
  end

  describe "bitwise guards" do
    test "band check on sampled flag" do
      assert Filters.bitwise_sampled?(encode_envelope(1, 10))
      assert Filters.bitwise_sampled?(encode_envelope(3, 10))
      assert Filters.bitwise_sampled?(encode_envelope(0xFF, 10))
    end

    test "rejects when sampled bit is not set" do
      refute Filters.bitwise_sampled?(encode_envelope(0, 10))
      refute Filters.bitwise_sampled?(encode_envelope(2, 10))
      refute Filters.bitwise_sampled?(encode_envelope(4, 10))
    end
  end

  describe "comparison guards" do
    test "greater-than check on message_type" do
      assert Filters.high_message_type?(encode_envelope(0, 200))
      refute Filters.high_message_type?(encode_envelope(0, 50))
      refute Filters.high_message_type?(encode_envelope(0, 100))
    end
  end

  describe "cross-field comparison" do
    test "detects slow spans via field difference" do
      now = System.system_time(:nanosecond)
      assert Filters.slow_span?(encode_span(1, 1, now, now + 2_000_000))
    end

    test "rejects fast spans" do
      now = System.system_time(:nanosecond)
      refute Filters.slow_span?(encode_span(1, 1, now, now + 500))
    end
  end

  describe "multiple where clauses (AND)" do
    test "matches when ALL conditions hold" do
      now = System.system_time(:nanosecond)
      assert Filters.sampled_server?(encode_span(1, 3, now, now + 100))
    end

    test "rejects when first condition fails" do
      now = System.system_time(:nanosecond)
      refute Filters.sampled_server?(encode_span(0, 3, now, now + 100))
    end

    test "rejects when second condition fails" do
      now = System.system_time(:nanosecond)
      refute Filters.sampled_server?(encode_span(1, 1, now, now + 100))
    end

    test "rejects when both conditions fail" do
      now = System.system_time(:nanosecond)
      refute Filters.sampled_server?(encode_span(0, 1, now, now + 100))
    end
  end

  describe "select mode" do
    test "returns field map on match" do
      bin = encode_envelope(1, 42)
      assert {:match, result} = Filters.extract_context(bin)
      assert result.trace_id == @trace_id
      assert result.span_id == 42
    end

    test "returns :no_match when guard fails" do
      bin = encode_envelope(0, 42)
      assert :no_match = Filters.extract_context(bin)
    end

    test "returns :no_match for non-binary" do
      assert :no_match = Filters.extract_context(nil)
    end
  end

  describe "Enum.filter integration" do
    test "filters a list of binaries efficiently" do
      bins =
        for flags <- [0, 1, 0, 1, 1, 0, 0, 1] do
          encode_envelope(flags, 10)
        end

      sampled = Enum.filter(bins, &Filters.sampled?/1)
      assert length(sampled) == 4
    end
  end

  describe "property tests" do
    property "sampled? matches iff flags == 1" do
      check all(
              flags <- StreamData.integer(0..0xFFFFFFFF),
              msg <- StreamData.integer(0..0xFFFF)
            ) do
        bin = encode_envelope(flags, msg)
        assert Filters.sampled?(bin) == (flags == 1)
      end
    end

    property "bitwise_sampled? matches iff lowest bit set" do
      check all(
              flags <- StreamData.integer(0..0xFFFFFFFF),
              msg <- StreamData.integer(0..0xFFFF)
            ) do
        bin = encode_envelope(flags, msg)
        assert Filters.bitwise_sampled?(bin) == (Bitwise.band(flags, 1) == 1)
      end
    end

    property "high_message_type? matches iff message_type > 100" do
      check all(
              flags <- StreamData.integer(0..0xFFFFFFFF),
              msg <- StreamData.integer(0..0xFFFF)
            ) do
        bin = encode_envelope(flags, msg)
        assert Filters.high_message_type?(bin) == msg > 100
      end
    end

    property "slow_span? matches iff duration > 1_000_000 ns" do
      check all(
              flags <- StreamData.integer(0..0xFFFFFFFF),
              kind <- StreamData.integer(0..255),
              start <- StreamData.integer(1_000_000_000..2_000_000_000),
              delta <- StreamData.integer(0..10_000_000)
            ) do
        bin = encode_span(flags, kind, start, start + delta)
        assert Filters.slow_span?(bin) == delta > 1_000_000
      end
    end

    property "extract_context returns trace_id and span_id on match" do
      check all(
              flags <- StreamData.member_of([0, 1]),
              msg <- StreamData.integer(0..0xFFFF)
            ) do
        bin = encode_envelope(flags, msg)

        case Filters.extract_context(bin) do
          {:match, result} ->
            assert flags == 1
            assert result.trace_id == @trace_id
            assert result.span_id == 42

          :no_match ->
            assert flags != 1
        end
      end
    end
  end
end
