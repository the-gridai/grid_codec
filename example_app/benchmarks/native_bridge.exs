defmodule NativeBench.Codec do
  use GridCodec.Struct, template_id: 65_000, schema_id: 65_001

  defcodec do
    field :number, :u32
    field :signed, :i64
    field :active, :bool
    field :name, :string8
  end
end

defmodule NativeBench do
  alias GridCodec.Native
  alias NativeBench.Codec

  require Codec

  def run do
    iterations = String.to_integer(System.get_env("ITERATIONS", "1000000"))
    message = %Codec{number: 42, signed: -7, active: true, name: "grid"}
    {:ok, binary} = Codec.encode(message)

    IO.puts("GridCodec operation matrix (same message and wire bytes)")

    IO.puts(
      "Run pure Rust separately with: cargo bench --manifest-path native/grid_codec/Cargo.toml"
    )

    measure("pure_elixir/field_access", iterations, fn -> Codec.get(binary, :number) end)
    measure("rustler/field_access", iterations, fn -> Native.benchmark_get_number(binary) end)

    measure("pure_elixir/encode", iterations, fn -> Codec.encode(message) end)

    measure("rustler/encode", iterations, fn ->
      Native.benchmark_encode(42, -7, true, "grid")
    end)

    measure("pure_elixir/decode", iterations, fn -> Codec.decode(binary) end)
    measure("rustler/decode", iterations, fn -> Native.benchmark_decode(binary) end)
  end

  defp measure(name, iterations, fun) do
    {microseconds, result} = :timer.tc(fn -> repeat(iterations, fun, nil) end)
    ns_per_operation = microseconds * 1_000 / iterations
    IO.puts("#{name}: #{Float.round(ns_per_operation, 1)} ns/op")
    result
  end

  defp repeat(0, _fun, result), do: result
  defp repeat(iterations, fun, _result), do: repeat(iterations - 1, fun, fun.())
end

NativeBench.run()
