alias GridCodec.Native

iterations = String.to_integer(System.get_env("ITERATIONS", "1000000"))
fixture = <<42::little-32, -7::little-signed-64, 1::8, 4::8, "grid"::binary>>
header = GridCodec.Header.encode(block_length: 32, template_id: 1, schema_id: 100, version: 2)

defmodule NativeBench do
  def measure(name, iterations, fun) do
    {microseconds, _} = :timer.tc(fn -> for _ <- 1..iterations, do: fun.() end)
    ns_per_operation = microseconds * 1_000 / iterations
    IO.puts("#{name}: #{Float.round(ns_per_operation, 1)} ns/op")
  end
end

NativeBench.measure("beam_header", iterations, fn -> GridCodec.Header.decode!(header) end)
NativeBench.measure("rust_header_nif", iterations, fn -> Native.read_header(header) end)

NativeBench.measure("beam_primitives", iterations, fn ->
  <<number::little-32, signed::little-signed-64, active::8, length::8, name::binary-size(length)>> =
    fixture

  {number, signed, active == 1, name}
end)

NativeBench.measure("rust_primitives_nif", iterations, fn -> Native.decode_primitives(fixture) end)
