defmodule ExampleApp.EnvelopeTarget do
  @moduledoc false

  alias ExampleApp.Bench.BinaryEnvelope

  @doc false
  def encode(fields) when is_map(fields) do
    BinaryEnvelope.encode(struct!(BinaryEnvelope, fields))
  end
end

defmodule ExampleApp.SpanToEnvelope do
  @moduledoc """
  Transcodes a `BinaryTraceContext` span into a `BinaryEnvelope`.

  Demonstrates `GridCodec.Transcoder` — extracting a subset of fields from
  one GridCodec binary and encoding them into another format without ever
  creating an intermediate struct for the *source*.

  The envelope is a compact routing header (trace_id, span_id, flags,
  message_type) suitable for pub/sub fan-out where recipients only need
  enough context to decide whether to request the full span.

  ## Usage

      alias ExampleApp.SpanToEnvelope
      alias ExampleApp.Bench.{BinaryTraceContext, BinaryEnvelope}

      {:ok, span_bin} = BinaryTraceContext.encode(span)
      {:ok, envelope_bin} = SpanToEnvelope.transcode(span_bin)

      # The envelope is a valid BinaryEnvelope binary
      {:ok, envelope} = BinaryEnvelope.decode(envelope_bin)
  """

  require ExampleApp.Bench.BinaryTraceContext

  use GridCodec.Transcoder,
    source: ExampleApp.Bench.BinaryTraceContext,
    target: ExampleApp.EnvelopeTarget

  field(:trace_id)
  field(:span_id)
  field(:flags)
  field :kind, to: :message_type
end
