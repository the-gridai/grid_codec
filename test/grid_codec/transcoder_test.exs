defmodule GridCodec.TranscoderTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  # ── Source codec ─────────────────────────────────────────────────────────

  defmodule SourceSpan do
    use GridCodec.Struct, template_id: 8900, schema_id: 89

    defcodec do
      field :trace_id, :uuid
      field :span_id, :u64
      field :flags, :u32
      field :kind, :u8
      field :start_time_ns, :timestamp_ns
      field :end_time_ns, :timestamp_ns
      field :name, :string16
    end
  end

  # ── Target encoder (simple map → binary round-trip via a second codec) ───

  defmodule TargetCompact do
    use GridCodec.Struct, template_id: 8901, schema_id: 89

    defcodec do
      field :tid, :uuid
      field :sid, :u64
      field :f, :u32
    end
  end

  defmodule CompactTarget do
    def encode(fields) when is_map(fields) do
      compact = struct!(TargetCompact, tid: fields.tid, sid: fields.sid, f: fields.f)
      TargetCompact.encode(compact)
    end
  end

  # ── Transcoder definition ────────────────────────────────────────────────

  defmodule SpanToCompact do
    use GridCodec.Transcoder,
      source: GridCodec.TranscoderTest.SourceSpan,
      target: GridCodec.TranscoderTest.CompactTarget

    field :trace_id, to: :tid
    field :span_id, to: :sid
    field :flags, to: :f
  end

  # ── Transform test ────────────────────────────────────────────────────────

  defmodule PlainTarget do
    def encode(fields), do: {:ok, fields}
  end

  defmodule WithTransform do
    use GridCodec.Transcoder,
      source: GridCodec.TranscoderTest.SourceSpan,
      target: GridCodec.TranscoderTest.PlainTarget

    field :flags, transform: &(&1 * 10)
    field(:kind)
  end

  # ── Tests ────────────────────────────────────────────────────────────────

  @trace_id :crypto.strong_rand_bytes(16)

  defp make_source do
    now = System.system_time(:nanosecond)

    span =
      struct!(SourceSpan,
        trace_id: @trace_id,
        span_id: 42,
        flags: 7,
        kind: 3,
        start_time_ns: now,
        end_time_ns: now + 1_000_000,
        name: "test.span"
      )

    {:ok, bin} = SourceSpan.encode(span)
    bin
  end

  describe "basic transcoding" do
    test "transcodes to a different codec without intermediate struct" do
      bin = make_source()
      assert {:ok, compact_bin} = SpanToCompact.transcode(bin)

      {:ok, decoded} = TargetCompact.decode(compact_bin)
      assert decoded.tid == @trace_id
      assert decoded.sid == 42
      assert decoded.f == 7
    end
  end

  describe "field rename" do
    test "maps source field to different target field name" do
      bin = make_source()
      {:ok, compact_bin} = SpanToCompact.transcode(bin)
      {:ok, decoded} = TargetCompact.decode(compact_bin)
      assert decoded.tid == @trace_id
    end
  end

  describe "field transform" do
    test "applies transform function during transcoding" do
      bin = make_source()
      {:ok, result} = WithTransform.transcode(bin)

      assert result.flags == 70
      assert result.kind == 3
    end
  end

  describe "preserves values" do
    property "transcode preserves field values for random inputs" do
      check all(
              tid <- StreamData.binary(length: 16),
              sid <- StreamData.integer(0..0xFFFFFFFFFFFFFFFF),
              flags <- StreamData.integer(0..0xFFFFFFFF)
            ) do
        now = System.system_time(:nanosecond)

        span =
          struct!(SourceSpan,
            trace_id: tid,
            span_id: sid,
            flags: flags,
            kind: 1,
            start_time_ns: now,
            end_time_ns: now + 100,
            name: "prop"
          )

        {:ok, src_bin} = SourceSpan.encode(span)
        {:ok, compact_bin} = SpanToCompact.transcode(src_bin)
        {:ok, decoded} = TargetCompact.decode(compact_bin)

        assert decoded.tid == tid
        assert decoded.sid == sid
        assert decoded.f == flags
      end
    end

    property "transform function is applied correctly" do
      check all(
              flags <- StreamData.integer(0..0xFFFFFFFE),
              kind <- StreamData.integer(0..254)
            ) do
        now = System.system_time(:nanosecond)

        span =
          struct!(SourceSpan,
            trace_id: :crypto.strong_rand_bytes(16),
            span_id: 1,
            flags: flags,
            kind: kind,
            start_time_ns: now,
            end_time_ns: now + 100,
            name: "tx"
          )

        {:ok, src_bin} = SourceSpan.encode(span)
        {:ok, result} = WithTransform.transcode(src_bin)

        assert result.flags == flags * 10
        assert result.kind == kind
      end
    end
  end
end
