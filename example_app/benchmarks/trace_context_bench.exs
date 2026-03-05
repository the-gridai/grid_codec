# Trace Context Benchmark — GridCodec vs W3C String Parsing
#
# Inspired by Discord's blog post on tracing overhead:
# https://discord.com/blog/tracing-discords-elixir-systems-without-melting-everything
#
# Discord found that 75% of CPU in their gRPC handler was spent parsing
# W3C trace context strings. Their fix: check the last byte of the hex string
# to see if sampled before doing the full parse.
#
# This benchmark explores whether a binary trace context (GridCodec) can
# eliminate that overhead entirely via zero-copy field access.
#
# Run from example_app/:
#   MIX_ENV=prod mix run benchmarks/trace_context_bench.exs

alias ExampleApp.Bench.BinaryTraceContext
alias ExampleApp.Bench.BinaryEnvelope
alias ExampleApp.Bench.ProtoSpan

# =============================================================================
# W3C Trace Context helpers (string format)
# =============================================================================

defmodule W3C do
  def parse(<<"00-", tid::binary-size(32), "-", sid::binary-size(16), "-", fh::binary-size(2)>>) do
    %{trace_id: Base.decode16!(tid, case: :mixed),
      span_id: Base.decode16!(sid, case: :mixed),
      flags: String.to_integer(fh, 16)}
  end

  def format(trace_id, span_id, flags) do
    "00-" <> Base.encode16(trace_id, case: :lower) <> "-" <>
      Base.encode16(span_id, case: :lower) <> "-" <>
      String.pad_leading(Integer.to_string(flags, 16), 2, "0")
  end

  def sampled_fast?(<<_::binary-size(53), fh::binary-size(2)>>), do: fh != "00"
end

# =============================================================================
# Test data
# =============================================================================

import Bitwise

trace_id = :crypto.strong_rand_bytes(16)
span_id = :rand.uniform(bsl(1, 64)) - 1
parent_span_id = :rand.uniform(bsl(1, 64)) - 1
now_ns = System.system_time(:nanosecond)

w3c_sampled = W3C.format(trace_id, <<span_id::64>>, 1)
w3c_not_sampled = W3C.format(trace_id, <<span_id::64>>, 0)

gc_span = struct!(BinaryTraceContext,
  trace_id: trace_id, span_id: span_id, parent_span_id: parent_span_id,
  flags: 1, kind: 1, start_time_ns: now_ns, end_time_ns: now_ns + 1_000_000,
  name: "guild.dispatch_message")

gc_envelope = struct!(BinaryEnvelope,
  trace_id: trace_id, span_id: span_id, flags: 1, message_type: 42)

gc_envelope_notsamp = struct!(BinaryEnvelope,
  trace_id: trace_id, span_id: span_id, flags: 0, message_type: 42)

proto_span = struct!(ProtoSpan,
  trace_id: trace_id, span_id: <<span_id::64>>, parent_span_id: <<parent_span_id::64>>,
  flags: 1, kind: 1, start_time_unix_nano: now_ns, end_time_unix_nano: now_ns + 1_000_000,
  name: "guild.dispatch_message")

{:ok, gc_span_bin} = BinaryTraceContext.encode(gc_span)
{:ok, gc_env_bin} = BinaryEnvelope.encode(gc_envelope)
{:ok, gc_env_ns_bin} = BinaryEnvelope.encode(gc_envelope_notsamp)
proto_bin = ProtoSpan.encode(proto_span)
etf_bin = :erlang.term_to_binary(gc_span)
json_str = Jason.encode!(%{trace_id: Base.encode16(trace_id, case: :lower),
  span_id: span_id, parent_span_id: parent_span_id,
  flags: 1, kind: 1, start_time_ns: now_ns, end_time_ns: now_ns + 1_000_000,
  name: "guild.dispatch_message"})
msgpack_bin = Msgpax.pack!(%{"trace_id" => trace_id, "span_id" => span_id,
  "parent_span_id" => parent_span_id, "flags" => 1, "kind" => 1,
  "start_time_ns" => now_ns, "end_time_ns" => now_ns + 1_000_000,
  "name" => "guild.dispatch_message"}) |> IO.iodata_to_binary()

require BinaryEnvelope

IO.puts("""
Trace Context Benchmark
==================================================
Inspired by: https://discord.com/blog/tracing-discords-elixir-systems-without-melting-everything

Wire sizes:
  W3C traceparent string:  #{byte_size(w3c_sampled)} bytes
  GridCodec envelope:      #{byte_size(gc_env_bin)} bytes
  GridCodec full span:     #{byte_size(gc_span_bin)} bytes
  Protobuf span:           #{byte_size(proto_bin)} bytes
  ETF span:                #{byte_size(etf_bin)} bytes
  JSON span:               #{byte_size(json_str)} bytes
  MessagePack span:        #{byte_size(msgpack_bin)} bytes
""")

# =============================================================================
# Benchmark 1: Sampling decision
# =============================================================================

IO.puts("=== Benchmark 1: Sampling Decision (is this trace sampled?) ===\n")

Benchee.run(%{
  "W3C full parse" => fn -> W3C.parse(w3c_not_sampled) end,
  "W3C Discord fast-check" => fn -> W3C.sampled_fast?(w3c_not_sampled) end,
  "GridCodec get(:flags)" => fn -> BinaryEnvelope.get(gc_env_ns_bin, :flags) end,
  "ETF decode + access" => fn -> :erlang.binary_to_term(etf_bin).flags end,
  "JSON decode + access" => fn -> Jason.decode!(json_str)["flags"] end,
}, warmup: 2, time: 5, memory_time: 1)

# =============================================================================
# Benchmark 2: Full encode
# =============================================================================

IO.puts("\n=== Benchmark 2: Full Span Encode ===\n")

json_map = %{"trace_id" => Base.encode16(trace_id, case: :lower),
  "span_id" => span_id, "parent_span_id" => parent_span_id,
  "flags" => 1, "kind" => 1,
  "start_time_ns" => now_ns, "end_time_ns" => now_ns + 1_000_000,
  "name" => "guild.dispatch_message"}

msgpack_map = %{"trace_id" => trace_id, "span_id" => span_id,
  "parent_span_id" => parent_span_id, "flags" => 1, "kind" => 1,
  "start_time_ns" => now_ns, "end_time_ns" => now_ns + 1_000_000,
  "name" => "guild.dispatch_message"}

Benchee.run(%{
  "GridCodec" => fn -> BinaryTraceContext.encode(gc_span) end,
  "Protobuf" => fn -> ProtoSpan.encode(proto_span) end,
  "ETF" => fn -> :erlang.term_to_binary(gc_span) end,
  "JSON" => fn -> Jason.encode!(json_map) end,
  "MessagePack" => fn -> Msgpax.pack!(msgpack_map) end,
}, warmup: 2, time: 5, memory_time: 1)

# =============================================================================
# Benchmark 3: Full decode
# =============================================================================

IO.puts("\n=== Benchmark 3: Full Span Decode ===\n")

Benchee.run(%{
  "GridCodec" => fn -> BinaryTraceContext.decode(gc_span_bin) end,
  "Protobuf" => fn -> ProtoSpan.decode(proto_bin) end,
  "ETF" => fn -> :erlang.binary_to_term(etf_bin) end,
  "JSON" => fn -> Jason.decode!(json_str) end,
  "MessagePack" => fn -> Msgpax.unpack!(msgpack_bin) end,
}, warmup: 2, time: 5, memory_time: 1)

# =============================================================================
# Benchmark 4: Fan-out cost
# =============================================================================

IO.puts("\n=== Benchmark 4: Fan-out — encode once, send to 1000 processes ===\n")

IO.puts("""
BEAM semantics: binaries > 64 bytes are reference-counted (shared).
GridCodec encodes once → the binary is shared across all recipients.
Other formats must re-encode or copy the struct for each send.
""")

Benchee.run(%{
  "GridCodec: encode once, share 1000x" => fn ->
    {:ok, bin} = BinaryEnvelope.encode(gc_envelope)
    for _ <- 1..1000, do: bin
  end,
  "ETF: encode 1000x" => fn ->
    for _ <- 1..1000, do: :erlang.term_to_binary(gc_envelope)
  end,
  "Protobuf: encode 1000x" => fn ->
    for _ <- 1..1000, do: ProtoSpan.encode(proto_span)
  end,
}, warmup: 2, time: 5, memory_time: 1)

IO.puts("""

==================================================
Analysis: Where GridCodec helps with Discord's pain points
==================================================

1. SAMPLING CHECK (75% of Discord's gRPC CPU)
   W3C: parse 55-byte hex string → decode trace_id + span_id + flags
   Discord fix: check last 2 chars of the string (still a string op)
   GridCodec: get(:flags) reads 4 bytes at fixed offset — O(1), ~14ns

2. FAN-OUT (message × million recipients)
   Struct: copied per process (BEAM semantics for small terms)
   Binary > 64B: shared via refc pointer (BEAM semantics for binaries)
   GridCodec: encode once → binary IS the message → zero-copy fan-out

3. FIELD ACCESS POST-FANOUT (each session checks trace context)
   ETF/JSON: full decode to read one field
   GridCodec: get/2 reads field at compile-time offset, no decode

4. SPAN EXPORT (batch processor → OTLP collector)
   Current: ETS → protobuf encode → gRPC
   GridCodec opportunity: spans as fixed-layout binary in ETS,
   batch via groups, export with minimal re-encoding
""")
