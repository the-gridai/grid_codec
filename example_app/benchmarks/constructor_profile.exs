# Constructor tprof analysis
#
# Run with: mix run benchmarks/constructor_profile.exs

defmodule ConstructorProfile do
  defmodule C do
    use GridCodec.Struct, template_id: 997, schema_id: 99, version: 1, validate: true

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
    typed = %{
      id: 42,
      count: 100,
      price: 50_000,
      active: true,
      score: -5,
      created_at: 1_700_000_000_000_000
    }

    string = %{
      "id" => "42",
      "count" => "100",
      "price" => "50000",
      "active" => "true",
      "score" => "-5",
      "created_at" => "2026-01-01T00:00:00Z"
    }

    bad = %{count: 5_000_000_000}
    n = 100_000

    for _ <- 1..1000, do: C.new(typed)

    IO.puts("=== new/1 typed (validate: true) — #{n} iterations ===")

    Mix.Tasks.Profile.Tprof.profile(
      fn ->
        for _ <- 1..n, do: C.new(typed)
        :ok
      end,
      type: :time,
      sort: :time,
      report: :total,
      set_on_spawn: false
    )

    IO.puts("\n=== new/1 string (coerce + validate) — #{n} iterations ===")

    Mix.Tasks.Profile.Tprof.profile(
      fn ->
        for _ <- 1..n, do: C.new(string)
        :ok
      end,
      type: :time,
      sort: :time,
      report: :total,
      set_on_spawn: false
    )

    IO.puts("\n=== new/1 error path (validation fail) — #{n} iterations ===")

    Mix.Tasks.Profile.Tprof.profile(
      fn ->
        for _ <- 1..n, do: C.new(bad)
        :ok
      end,
      type: :time,
      sort: :time,
      report: :total,
      set_on_spawn: false
    )
  end
end

ConstructorProfile.run()
