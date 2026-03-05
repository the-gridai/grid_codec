defmodule ExampleApp.SpanFilters do
  @moduledoc """
  Match predicates for `BinaryTraceContext` span binaries.

  Uses `GridCodec.Match` to generate compiled filter functions that evaluate
  conditions directly on the binary — no full decode required.

  ## Usage

      alias ExampleApp.SpanFilters

      {:ok, bin} = BinaryTraceContext.encode(span)

      SpanFilters.sampled?(bin)       #=> true | false
      SpanFilters.slow?(bin)          #=> true | false

      # With ETS scan
      :ets.foldl(
        fn {_k, bin}, acc ->
          if SpanFilters.sampled?(bin), do: [bin | acc], else: acc
        end,
        [],
        span_table
      )
  """

  use GridCodec.Match

  alias ExampleApp.Bench.BinaryTraceContext
  require BinaryTraceContext

  @doc "Returns `true` when the trace-level sampled bit (0x01) is set in `flags`."
  defmatch :sampled?, BinaryTraceContext do
    where(band(flags, 0x01) == 1)
  end

  @doc "Returns `true` when the span duration exceeds 5 ms (5,000,000 ns)."
  defmatch :slow?, BinaryTraceContext do
    where(end_time_ns - start_time_ns > 5_000_000)
  end

  @doc "Returns `true` when the span is a server span (`kind == 3`)."
  defmatch :server_span?, BinaryTraceContext do
    where(kind == 3)
  end

  @doc "Returns `true` when the span is both sampled and a server span."
  defmatch :sampled_server?, BinaryTraceContext do
    where(band(flags, 1) == 1)
    where(kind == 3)
  end

  @doc """
  Returns `{:match, %{trace_id: ..., span_id: ..., start_time_ns: ...}}`
  for slow sampled spans, or `:no_match` otherwise.

  Useful for extracting context from spans that need alerting.
  """
  defmatch :alert_context, BinaryTraceContext, select: [:trace_id, :span_id, :start_time_ns] do
    where(band(flags, 1) == 1)
    where(end_time_ns - start_time_ns > 10_000_000)
  end
end
