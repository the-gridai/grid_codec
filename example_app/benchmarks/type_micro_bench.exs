# Per-Type Micro Benchmark
#
# Measures encode + decode latency for each built-in type in isolation.
# Use to detect regressions after optimizations.
#
# Run from example_app/:
#   mix run benchmarks/type_micro_bench.exs

defmodule TypeBench do
  defmodule U8Codec do
    use GridCodec.Struct, template_id: 900, schema_id: 99
    defcodec do
      field :val, :u8
    end
  end

  defmodule U16Codec do
    use GridCodec.Struct, template_id: 901, schema_id: 99
    defcodec do
      field :val, :u16
    end
  end

  defmodule U32Codec do
    use GridCodec.Struct, template_id: 902, schema_id: 99
    defcodec do
      field :val, :u32
    end
  end

  defmodule U64Codec do
    use GridCodec.Struct, template_id: 903, schema_id: 99
    defcodec do
      field :val, :u64
    end
  end

  defmodule I8Codec do
    use GridCodec.Struct, template_id: 904, schema_id: 99
    defcodec do
      field :val, :i8
    end
  end

  defmodule I16Codec do
    use GridCodec.Struct, template_id: 905, schema_id: 99
    defcodec do
      field :val, :i16
    end
  end

  defmodule I32Codec do
    use GridCodec.Struct, template_id: 906, schema_id: 99
    defcodec do
      field :val, :i32
    end
  end

  defmodule I64Codec do
    use GridCodec.Struct, template_id: 907, schema_id: 99
    defcodec do
      field :val, :i64
    end
  end

  defmodule F32Codec do
    use GridCodec.Struct, template_id: 908, schema_id: 99
    defcodec do
      field :val, :f32
    end
  end

  defmodule F64Codec do
    use GridCodec.Struct, template_id: 909, schema_id: 99
    defcodec do
      field :val, :f64
    end
  end

  defmodule BoolCodec do
    use GridCodec.Struct, template_id: 910, schema_id: 99
    defcodec do
      field :val, :bool
    end
  end

  defmodule UUIDCodec do
    use GridCodec.Struct, template_id: 911, schema_id: 99
    defcodec do
      field :val, :uuid
    end
  end

  defmodule UUIDStringCodec do
    use GridCodec.Struct, template_id: 912, schema_id: 99
    defcodec do
      field :val, :uuid_string
    end
  end

  defmodule DecimalCodec do
    use GridCodec.Struct, template_id: 913, schema_id: 99
    defcodec do
      field :val, :decimal
    end
  end

  defmodule PositiveDecimalCodec do
    use GridCodec.Struct, template_id: 914, schema_id: 99
    defcodec do
      field :val, :positive_decimal
    end
  end

  defmodule TimestampUsCodec do
    use GridCodec.Struct, template_id: 915, schema_id: 99
    defcodec do
      field :val, :timestamp_us
    end
  end

  defmodule StringCodec do
    use GridCodec.Struct, template_id: 916, schema_id: 99
    defcodec do
      field :val, :string
    end
  end

  defmodule ScaledDecimalCodec do
    use GridCodec.Struct, template_id: 917, schema_id: 99
    defcodec do
      field :val, {:decimal, scale: 8}
    end
  end
end

uuid_bytes = GridCodec.Types.UUID.generate_v4()
uuid_string = GridCodec.Types.UUIDString.format_uuid(uuid_bytes)
ts = System.system_time(:microsecond)

types = [
  {"u8", TypeBench.U8Codec, %{val: 42}},
  {"u16", TypeBench.U16Codec, %{val: 1000}},
  {"u32", TypeBench.U32Codec, %{val: 100_000}},
  {"u64", TypeBench.U64Codec, %{val: 1_000_000_000}},
  {"i8", TypeBench.I8Codec, %{val: -42}},
  {"i16", TypeBench.I16Codec, %{val: -1000}},
  {"i32", TypeBench.I32Codec, %{val: -100_000}},
  {"i64", TypeBench.I64Codec, %{val: -1_000_000_000}},
  {"f32", TypeBench.F32Codec, %{val: 3.14}},
  {"f64", TypeBench.F64Codec, %{val: 3.141592653589793}},
  {"bool", TypeBench.BoolCodec, %{val: true}},
  {"uuid", TypeBench.UUIDCodec, %{val: uuid_bytes}},
  {"uuid_string", TypeBench.UUIDStringCodec, %{val: uuid_string}},
  {"decimal", TypeBench.DecimalCodec, %{val: Decimal.new("123.45")}},
  {"positive_decimal", TypeBench.PositiveDecimalCodec, %{val: Decimal.new("123.45")}},
  {"timestamp_us", TypeBench.TimestampUsCodec, %{val: ts}},
  {"string", TypeBench.StringCodec, %{val: "hello world"}},
  {"{:decimal, scale: 8}", TypeBench.ScaledDecimalCodec, %{val: Decimal.new("123.45000000")}}
]

pre_encoded =
  Enum.map(types, fn {name, mod, data} ->
    struct = struct(mod, data)
    {:ok, binary} = mod.encode(struct)
    {name, mod, struct, binary}
  end)

IO.puts("""

Per-Type Micro Benchmark
========================
Each type is tested in isolation with a single-field codec.
""")

IO.puts("=== Encode ===\n")

encode_benches =
  Enum.into(pre_encoded, %{}, fn {name, mod, struct, _binary} ->
    {"encode #{name}", fn -> {:ok, _} = mod.encode(struct) end}
  end)

Benchee.run(encode_benches,
  warmup: 1,
  time: 3,
  memory_time: 0.5,
  print: [configuration: false]
)

IO.puts("\n=== Decode ===\n")

decode_benches =
  Enum.into(pre_encoded, %{}, fn {name, mod, _struct, binary} ->
    {"decode #{name}", fn -> {:ok, _} = mod.decode(binary) end}
  end)

Benchee.run(decode_benches,
  warmup: 1,
  time: 3,
  memory_time: 0.5,
  print: [configuration: false]
)

IO.puts("\n=== Zero-Copy Get (representative types) ===\n")

defmodule TypeBench.GetBench do
  require TypeBench.U64Codec
  require TypeBench.UUIDCodec
  require TypeBench.UUIDStringCodec
  require TypeBench.BoolCodec
  require TypeBench.DecimalCodec
  require TypeBench.TimestampUsCodec

  def get_u64(bin), do: TypeBench.U64Codec.get(bin, :val)
  def get_uuid(bin), do: TypeBench.UUIDCodec.get(bin, :val)
  def get_uuid_string(bin), do: TypeBench.UUIDStringCodec.get(bin, :val)
  def get_bool(bin), do: TypeBench.BoolCodec.get(bin, :val)
  def get_decimal(bin), do: TypeBench.DecimalCodec.get(bin, :val)
  def get_timestamp(bin), do: TypeBench.TimestampUsCodec.get(bin, :val)
end

u64_bin = Enum.find_value(pre_encoded, fn {"u64", _, _, b} -> b; _ -> nil end)
uuid_bin = Enum.find_value(pre_encoded, fn {"uuid", _, _, b} -> b; _ -> nil end)
uuid_str_bin = Enum.find_value(pre_encoded, fn {"uuid_string", _, _, b} -> b; _ -> nil end)
bool_bin = Enum.find_value(pre_encoded, fn {"bool", _, _, b} -> b; _ -> nil end)
dec_bin = Enum.find_value(pre_encoded, fn {"decimal", _, _, b} -> b; _ -> nil end)
ts_bin = Enum.find_value(pre_encoded, fn {"timestamp_us", _, _, b} -> b; _ -> nil end)

Benchee.run(
  %{
    "get u64" => fn -> TypeBench.GetBench.get_u64(u64_bin) end,
    "get uuid" => fn -> TypeBench.GetBench.get_uuid(uuid_bin) end,
    "get uuid_string" => fn -> TypeBench.GetBench.get_uuid_string(uuid_str_bin) end,
    "get bool" => fn -> TypeBench.GetBench.get_bool(bool_bin) end,
    "get decimal" => fn -> TypeBench.GetBench.get_decimal(dec_bin) end,
    "get timestamp_us" => fn -> TypeBench.GetBench.get_timestamp(ts_bin) end
  },
  warmup: 1,
  time: 3,
  print: [configuration: false]
)

IO.puts("\n=== UUID Generation ===\n")

Benchee.run(
  %{
    "UUID.generate_v4" => fn -> GridCodec.Types.UUID.generate_v4() end,
    "UUID.generate_v7" => fn -> GridCodec.Types.UUID.generate_v7() end,
    ":crypto.strong_rand_bytes(16)" => fn -> :crypto.strong_rand_bytes(16) end
  },
  warmup: 1,
  time: 3,
  memory_time: 0.5,
  print: [configuration: false]
)
