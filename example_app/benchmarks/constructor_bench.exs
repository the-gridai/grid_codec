# Constructor & Validation Benchmark
#
# Measures overhead of new/1, coercion, validation, and content_hash.
# Compares against raw struct creation to quantify the cost of safety.
#
# Run with: mix run benchmarks/constructor_bench.exs

defmodule ConstructorBench do
  defmodule Validated do
    use GridCodec.Struct,
      template_id: 995,
      schema_id: 99,
      version: 1,
      validate: true

    defcodec do
      field :id, :u64
      field :count, :u32
      field :price, :i64
      field :active, :bool
      field :score, :i8
      field :created_at, :timestamp_us
    end
  end

  defmodule Unvalidated do
    use GridCodec.Struct,
      template_id: 996,
      schema_id: 99,
      version: 1,
      validate: false

    defcodec do
      field :id, :u64
      field :count, :u32
      field :price, :i64
      field :active, :bool
      field :score, :i8
      field :created_at, :timestamp_us
    end
  end

  def run do
    IO.puts("Constructor & Validation Benchmark")
    IO.puts("===================================\n")

    typed_attrs = %{
      id: 42,
      count: 100,
      price: 50_000,
      active: true,
      score: -5,
      created_at: 1_700_000_000_000_000
    }

    string_attrs = %{
      "id" => "42",
      "count" => "100",
      "price" => "50000",
      "active" => "true",
      "score" => "-5",
      "created_at" => "2026-01-01T00:00:00Z"
    }

    kw_attrs = [
      id: 42,
      count: 100,
      price: 50_000,
      active: true,
      score: -5,
      created_at: 1_700_000_000_000_000
    ]

    bad_attrs = %{count: 5_000_000_000}
    bad_string = %{"count" => "not_a_number"}

    struct_val = %Validated{
      id: 42,
      count: 100,
      price: 50_000,
      active: true,
      score: -5,
      created_at: 1_700_000_000_000_000
    }

    struct_unval = %Unvalidated{
      id: 42,
      count: 100,
      price: 50_000,
      active: true,
      score: -5,
      created_at: 1_700_000_000_000_000
    }

    # -----------------------------------------------------------------
    # 1. Constructor overhead: raw struct vs new/1
    # -----------------------------------------------------------------
    IO.puts("--- 1. Constructor overhead ---\n")

    Benchee.run(
      %{
        "raw struct literal" => fn ->
          %Validated{
            id: 42,
            count: 100,
            price: 50_000,
            active: true,
            score: -5,
            created_at: 1_700_000_000_000_000
          }
        end,
        "struct!/2" => fn -> struct!(Validated, typed_attrs) end,
        "new/1 typed (no validate)" => fn -> Unvalidated.new(typed_attrs) end,
        "new/1 typed (validate: true)" => fn -> {:ok, _} = Validated.new(typed_attrs) end,
        "new/1 keyword" => fn -> Validated.new(kw_attrs) end
      },
      warmup: 2,
      time: 5,
      memory_time: 1
    )

    # -----------------------------------------------------------------
    # 2. Coercion overhead: typed vs string input
    # -----------------------------------------------------------------
    IO.puts("\n--- 2. Coercion overhead ---\n")

    Benchee.run(
      %{
        "new/1 typed input" => fn -> Validated.new(typed_attrs) end,
        "new/1 string input (coerce)" => fn -> Validated.new(string_attrs) end
      },
      warmup: 2,
      time: 5,
      memory_time: 1
    )

    # -----------------------------------------------------------------
    # 3. Error path speed: how fast do we fail?
    # -----------------------------------------------------------------
    IO.puts("\n--- 3. Error path speed ---\n")

    Benchee.run(
      %{
        "new/1 valid (happy path)" => fn -> Validated.new(typed_attrs) end,
        "new/1 validation error (first field)" => fn -> Validated.new(bad_attrs) end,
        "new/1 cast error (string)" => fn -> Validated.new(bad_string) end
      },
      warmup: 2,
      time: 5,
      memory_time: 1
    )

    # -----------------------------------------------------------------
    # 4. content_hash overhead
    # -----------------------------------------------------------------
    IO.puts("\n--- 4. content_hash vs encode ---\n")

    Benchee.run(
      %{
        "encode/1" => fn -> {:ok, _} = Validated.encode(struct_val) end,
        "content_hash/1" => fn -> Validated.content_hash(struct_val) end
      },
      warmup: 2,
      time: 5,
      memory_time: 1
    )

    # -----------------------------------------------------------------
    # 5. decode_only vs full decode
    # -----------------------------------------------------------------
    IO.puts("\n--- 5. decode_only vs full decode ---\n")

    {:ok, binary} = Validated.encode(struct_val)

    Benchee.run(
      %{
        "full decode/1" => fn -> Validated.decode(binary) end,
        "decode_only [:count, :active]" => fn ->
          Validated.decode_only(binary, [:count, :active])
        end,
        "decode_only [:price]" => fn -> Validated.decode_only(binary, [:price]) end
      },
      warmup: 2,
      time: 5,
      memory_time: 1
    )

    # -----------------------------------------------------------------
    # 6. Full pipeline: new → encode → decode
    # -----------------------------------------------------------------
    IO.puts("\n--- 6. Full pipeline: new → encode → decode ---\n")

    Benchee.run(
      %{
        "struct! → encode → decode (no validation)" => fn ->
          s = struct!(Unvalidated, typed_attrs)
          {:ok, bin} = Unvalidated.encode(s)
          Unvalidated.decode(bin)
        end,
        "new → encode → decode (validated)" => fn ->
          {:ok, s} = Validated.new(typed_attrs)
          {:ok, bin} = Validated.encode(s)
          Validated.decode(bin)
        end,
        "new(string) → encode → decode (coerce+validate)" => fn ->
          {:ok, s} = Validated.new(string_attrs)
          {:ok, bin} = Validated.encode(s)
          Validated.decode(bin)
        end
      },
      warmup: 2,
      time: 5,
      memory_time: 1
    )
  end
end

ConstructorBench.run()
