defmodule ExampleApp.Bench.BinaryTraceContext do
  use GridCodec.Struct, template_id: 9900, schema_id: 99

  defcodec do
    field :trace_id, :uuid
    field :span_id, :u64
    field :parent_span_id, :u64
    field :flags, :u32
    field :kind, :u8
    field :start_time_ns, :timestamp_ns
    field :end_time_ns, :timestamp_ns
    field :name, :string16
  end
end

defmodule ExampleApp.Bench.BinaryEnvelope do
  use GridCodec.Struct, template_id: 9901, schema_id: 99

  defcodec do
    field :trace_id, :uuid
    field :span_id, :u64
    field :flags, :u32
    field :message_type, :u16
  end
end

defmodule ExampleApp.Bench.ProtoSpan do
  use Protobuf, protoc_gen_elixir_version: "0.13.0", syntax: :proto3

  field :trace_id, 1, type: :bytes
  field :span_id, 2, type: :bytes
  field :parent_span_id, 4, type: :bytes
  field :flags, 16, type: :fixed32
  field :kind, 6, type: :int32
  field :start_time_unix_nano, 7, type: :fixed64
  field :end_time_unix_nano, 8, type: :fixed64
  field :name, 5, type: :string
end
