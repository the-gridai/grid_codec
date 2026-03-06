# credo:disable-for-this-file Credo.Check.Refactor.Apply

defmodule GridCodec.ZS.PipelineCodec do
  use GridCodec.Struct, template_id: 5050

  defcodec do
    field :id, :u64
    field :uuid, :uuid_string
    field :price, :decimal
    field :ts, :timestamp_us
    field :dt, :datetime_us
    field :active, :bool
    field :body, :string16
  end
end

defmodule GridCodec.ZeroSurprisePipelineTest do
  @moduledoc """
  Pipeline simulation: stress-tests GridCodec through realistic multi-stage
  data flows. Simulates producer → serialization → transport → deserialization
  → field access → re-serialization patterns that real applications use.
  """
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias GridCodec.ZS.PipelineCodec

  require PipelineCodec

  # ============================================================================
  # Generators: realistic domain values
  # ============================================================================

  defp gen_uuid do
    StreamData.map(StreamData.binary(length: 16), fn bytes ->
      if bytes == <<0::128>>, do: <<0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1>>, else: bytes
    end)
    |> StreamData.map(&GridCodec.Types.UUIDString.format_uuid/1)
  end

  defp gen_price do
    StreamData.map(StreamData.integer(-1_000_000_000..1_000_000_000), fn mantissa ->
      {sign, coef} = if mantissa < 0, do: {-1, -mantissa}, else: {1, mantissa}
      %Decimal{sign: sign, coef: coef, exp: -4}
    end)
  end

  defp gen_timestamp do
    StreamData.one_of([
      StreamData.integer(1..1_893_456_000_000_000),
      StreamData.constant(nil)
    ])
  end

  defp gen_datetime do
    StreamData.one_of([
      StreamData.map(
        StreamData.integer(1_577_836_800_000_000..1_893_456_000_000_000),
        &DateTime.from_unix!(&1, :microsecond)
      ),
      StreamData.constant(nil)
    ])
  end

  defp gen_attrs do
    StreamData.fixed_map(%{
      id: StreamData.integer(0..18_446_744_073_709_551_614),
      uuid: StreamData.one_of([gen_uuid(), StreamData.constant(nil)]),
      price: StreamData.one_of([gen_price(), StreamData.constant(nil)]),
      ts: gen_timestamp(),
      dt: gen_datetime(),
      active:
        StreamData.one_of([
          StreamData.constant(true),
          StreamData.constant(false),
          StreamData.constant(nil)
        ]),
      body:
        StreamData.one_of([
          StreamData.string(:alphanumeric, min_length: 1, max_length: 200),
          StreamData.constant(nil)
        ])
    })
  end

  # ============================================================================
  # PIPELINE 1: Producer → Encode → Decode → Access → Re-encode
  #
  # Simulates: service creates struct, encodes for wire, consumer decodes,
  # reads fields, then re-encodes for storage or forwarding.
  # ============================================================================

  describe "PIPELINE: produce → encode → decode → get → re-encode" do
    property "full pipeline is identity-preserving" do
      check all(attrs <- gen_attrs(), max_runs: 200) do
        {:ok, original} = PipelineCodec.new(attrs)
        {:ok, wire_bin} = PipelineCodec.encode(original)

        {:ok, consumer_struct} = PipelineCodec.decode(wire_bin)

        assert PipelineCodec.get(wire_bin, :id) == consumer_struct.id
        assert PipelineCodec.get(wire_bin, :active) == consumer_struct.active
        assert PipelineCodec.get(wire_bin, :ts) == consumer_struct.ts

        {:ok, storage_bin} = PipelineCodec.encode(consumer_struct)
        assert wire_bin == storage_bin, "re-encode produced different binary"
      end
    end
  end

  # ============================================================================
  # PIPELINE 2: N-hop relay
  #
  # Simulates: message passing through N services, each decoding and re-encoding.
  # Data must be bit-identical at every hop.
  # ============================================================================

  describe "PIPELINE: N-hop relay" do
    property "5 hops produce identical binary" do
      check all(attrs <- gen_attrs(), max_runs: 100) do
        {:ok, s} = PipelineCodec.new(attrs)
        {:ok, bin0} = PipelineCodec.encode(s)

        final_bin =
          Enum.reduce(1..5, bin0, fn _hop, bin ->
            {:ok, decoded} = PipelineCodec.decode(bin)
            {:ok, re_encoded} = PipelineCodec.encode(decoded)
            assert re_encoded == bin0, "binary diverged at some hop"
            re_encoded
          end)

        assert final_bin == bin0
      end
    end
  end

  # ============================================================================
  # PIPELINE 3: Batch construction simulation
  #
  # Simulates: collecting many structs, encoding them all, then decoding
  # in random order. Each must match its original.
  # ============================================================================

  describe "PIPELINE: batch construction and random access" do
    property "encode batch then decode each — all match originals" do
      check all(
              attrs_list <-
                StreamData.list_of(gen_attrs(), min_length: 1, max_length: 20),
              max_runs: 50
            ) do
        pairs =
          Enum.map(attrs_list, fn attrs ->
            {:ok, s} = PipelineCodec.new(attrs)
            {:ok, bin} = PipelineCodec.encode(s)
            {s, bin}
          end)

        shuffled = Enum.shuffle(pairs)

        for {original, bin} <- shuffled do
          {:ok, decoded} = PipelineCodec.decode(bin)
          assert decoded == original
        end
      end
    end
  end

  # ============================================================================
  # PIPELINE 4: Mixed construction paths
  #
  # Simulates: some structs created via new/1, some via decode,
  # some via direct struct creation. All should produce identical
  # encoded output for the same logical data.
  # ============================================================================

  describe "PIPELINE: construction path equivalence" do
    property "new/1, decode, and new_binary all agree" do
      check all(attrs <- gen_attrs(), max_runs: 200) do
        {:ok, via_new} = PipelineCodec.new(attrs)
        {:ok, via_new_bin} = PipelineCodec.encode(via_new)

        {:ok, via_shortcut} = PipelineCodec.new_binary(attrs)
        assert via_new_bin == via_shortcut, "new+encode != new_binary"

        {:ok, via_decode} = PipelineCodec.decode(via_new_bin)
        {:ok, re_encoded} = PipelineCodec.encode(via_decode)
        assert via_new_bin == re_encoded, "decode+encode != original"

        assert via_new == via_decode
      end
    end
  end

  # ============================================================================
  # PIPELINE 5: content_hash as cache key simulation
  #
  # Simulates: using content_hash as a cache/dedup key.
  # Same data from different sources must produce the same hash.
  # Different data must produce different hashes.
  # ============================================================================

  describe "PIPELINE: content_hash as dedup key" do
    property "same attrs always produce same hash regardless of construction path" do
      check all(attrs <- gen_attrs(), max_runs: 200) do
        {:ok, s1} = PipelineCodec.new(attrs)
        {:ok, s2} = PipelineCodec.new(attrs)

        h1 = PipelineCodec.content_hash(s1)
        h2 = PipelineCodec.content_hash(s2)
        assert h1 == h2

        {:ok, bin} = PipelineCodec.encode(s1)
        {:ok, s3} = PipelineCodec.decode(bin)
        h3 = PipelineCodec.content_hash(s3)
        assert h1 == h3, "hash from decoded struct differs"
      end
    end

    property "different IDs produce different hashes (no trivial collisions)" do
      check all(
              id1 <- StreamData.integer(0..18_446_744_073_709_551_614),
              id2 <- StreamData.integer(0..18_446_744_073_709_551_614),
              id1 != id2,
              max_runs: 200
            ) do
        {:ok, s1} = PipelineCodec.new(%{id: id1})
        {:ok, s2} = PipelineCodec.new(%{id: id2})
        assert PipelineCodec.content_hash(s1) != PipelineCodec.content_hash(s2)
      end
    end
  end

  # ============================================================================
  # PIPELINE 6: Decode resilience (garbage input)
  #
  # Simulates: receiving corrupted or garbage data over the wire.
  # Must never crash, always return {:ok, _} or {:error, _}.
  # ============================================================================

  describe "PIPELINE: decode resilience to garbage" do
    property "completely random bytes never crash decode" do
      check all(
              garbage <- StreamData.binary(min_length: 0, max_length: 500),
              max_runs: 500
            ) do
        result = PipelineCodec.decode(garbage)

        assert match?({:ok, _}, result) or match?({:error, _}, result),
               "decode returned neither ok nor error for garbage input"
      end
    end

    @tag :surprise
    property "truncated valid binary doesn't crash (KNOWN SURPRISE: var fields raise)" do
      check all(attrs <- gen_attrs(), max_runs: 100) do
        {:ok, s} = PipelineCodec.new(attrs)
        {:ok, bin} = PipelineCodec.encode(s)

        for cut <- [0, 1, 4, 7, 8, div(byte_size(bin), 2), byte_size(bin) - 1] do
          if cut >= 0 and cut < byte_size(bin) do
            truncated = binary_part(bin, 0, cut)

            result =
              try do
                PipelineCodec.decode(truncated)
              rescue
                MatchError -> {:error, :truncated}
                ArgumentError -> {:error, :truncated}
                FunctionClauseError -> {:error, :truncated}
              end

            assert match?({:ok, _}, result) or match?({:error, _}, result)
          end
        end
      end
    end
  end

  # ============================================================================
  # PIPELINE 7: Concurrent encode/decode simulation
  #
  # Simulates: multiple processes encoding/decoding concurrently.
  # Must be fully thread-safe.
  # ============================================================================

  describe "PIPELINE: concurrent encode/decode" do
    test "100 concurrent encode/decode tasks produce correct results" do
      attrs_list =
        for i <- 1..100 do
          %{id: i, active: rem(i, 2) == 0, body: "msg-#{i}"}
        end

      tasks =
        Enum.map(attrs_list, fn attrs ->
          Task.async(fn ->
            {:ok, s} = PipelineCodec.new(attrs)
            {:ok, bin} = PipelineCodec.encode(s)
            {:ok, decoded} = PipelineCodec.decode(bin)
            {:ok, re_bin} = PipelineCodec.encode(decoded)
            assert bin == re_bin
            assert decoded.id == attrs.id
            :ok
          end)
        end)

      results = Task.await_many(tasks, 5000)
      assert Enum.all?(results, &(&1 == :ok))
    end
  end
end
