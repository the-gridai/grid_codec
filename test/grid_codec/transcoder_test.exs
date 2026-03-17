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

  defmodule ValidatedSource do
    use GridCodec.Struct,
      template_id: 8902,
      schema_id: 89,
      validate: true

    defcodec do
      field :start_ns, :i64
      field :end_ns, :i64
      field :status, :u8
    end

    validations do
      validate(compare(:end_ns, :>=, :start_ns),
        name: :source_order,
        category: :invariant
      )
    end
  end

  defmodule RawSource do
    use GridCodec.Struct,
      template_id: 8902,
      schema_id: 89,
      validate: false

    defcodec do
      field :start_ns, :i64
      field :end_ns, :i64
      field :status, :u8
    end
  end

  defmodule ValidatedTarget do
    use GridCodec.Struct,
      template_id: 8904,
      schema_id: 89,
      validate: true

    defcodec do
      field :start_ns, :i64
      field :end_ns, :i64
      field :status, :u8
    end

    validations do
      invariant :target_positive_duration do
        where(end_ns > start_ns)
      end
    end
  end

  defmodule RawTarget do
    use GridCodec.Struct,
      template_id: 8905,
      schema_id: 89,
      validate: false

    defcodec do
      field :start_ns, :i64
      field :end_ns, :i64
      field :status, :u8
    end
  end

  defmodule ValidationAwareTarget do
    def encode(fields) when is_map(fields),
      do: GridCodec.TranscoderTest.RawTarget.new_binary(fields)

    def new_binary(fields) when is_map(fields),
      do: GridCodec.TranscoderTest.ValidatedTarget.new_binary(fields)
  end

  defmodule SourceValidationTranscoder do
    use GridCodec.Transcoder,
      source: GridCodec.TranscoderTest.ValidatedSource,
      target: GridCodec.TranscoderTest.PlainTarget

    field(:start_ns)
    field(:end_ns)
    field(:status)
  end

  defmodule TargetValidationTranscoder do
    use GridCodec.Transcoder,
      source: GridCodec.TranscoderTest.ValidatedSource,
      target: GridCodec.TranscoderTest.ValidationAwareTarget,
      validate: :target

    field(:start_ns)
    field(:end_ns)
    field(:status)
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

  describe "validation modes" do
    test "validate: :source rejects invalid source binaries" do
      {:ok, invalid_bin} = RawSource.new_binary(start_ns: 5, end_ns: 3, status: 1)

      assert {:ok, %{start_ns: 5, end_ns: 3, status: 1}} =
               SourceValidationTranscoder.transcode(invalid_bin)

      assert {:error, %GridCodec.ValidationError{} = error} =
               SourceValidationTranscoder.transcode(invalid_bin, validate: :source)

      assert error.details.name == :source_order
    end

    test "validate: :target uses validated target encoding and can be opted out" do
      {:ok, src_bin} = ValidatedSource.new_binary(start_ns: 5, end_ns: 5, status: 1)

      assert {:error, %GridCodec.ValidationError{} = error} =
               TargetValidationTranscoder.transcode(src_bin)

      assert error.details.name == :target_positive_duration

      assert {:ok, raw_bin} = TargetValidationTranscoder.transcode(src_bin, validate: false)
      assert {:ok, decoded} = RawTarget.decode(raw_bin)
      assert decoded.start_ns == 5
      assert decoded.end_ns == 5
      assert decoded.status == 1
    end

    test "validate: :both applies source validation before target validation" do
      {:ok, invalid_bin} = RawSource.new_binary(start_ns: 7, end_ns: 3, status: 1)

      assert {:error, %GridCodec.ValidationError{} = error} =
               TargetValidationTranscoder.transcode(invalid_bin, validate: :both)

      assert error.details.name == :source_order
    end

    test "validate: true aliases :both" do
      {:ok, invalid_bin} = RawSource.new_binary(start_ns: 7, end_ns: 3, status: 1)

      assert {:error, %GridCodec.ValidationError{} = error} =
               TargetValidationTranscoder.transcode(invalid_bin, validate: true)

      assert error.details.name == :source_order
    end
  end
end
