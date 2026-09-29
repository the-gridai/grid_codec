defmodule GridCodec.NativeTest do
  use ExUnit.Case, async: true

  alias GridCodec.Native
  alias GridCodec.Native.Header
  alias GridCodec.Native.Nif
  alias GridCodec.NativeBenchmarkCodec

  test "Rust reads headers encoded by Elixir" do
    binary = GridCodec.Header.encode(block_length: 32, template_id: 1, schema_id: 100, version: 2)

    assert Nif.read_header(binary) == %Header{
             block_length: 32,
             template_id: 1,
             schema_id: 100,
             version: 2
           }
  end

  test "Rust and Elixir agree on the primitive fixture" do
    expected = <<42::little-32, -7::little-signed-64, 1::8, 4::8, "grid"::binary>>
    assert Native.encode_primitives(42, -7, true, "grid") == expected
    assert Native.decode_primitives(expected) == {42, -7, true, "grid"}
  end

  describe "shared Elixir and Rust codec cases" do
    setup do
      message = %NativeBenchmarkCodec{number: 42, signed: -7, active: true, name: "grid"}
      {:ok, binary} = NativeBenchmarkCodec.encode(message)
      %{binary: binary, message: message}
    end

    test "both implementations encode the same bytes", %{binary: binary, message: message} do
      assert Native.benchmark_encode(42, -7, true, "grid") == binary
      assert {:ok, ^binary} = NativeBenchmarkCodec.encode(message)
    end

    test "both implementations decode the same values", %{binary: binary, message: message} do
      assert Native.benchmark_decode(binary) == {42, -7, true, "grid"}
      assert NativeBenchmarkCodec.decode(binary) == {:ok, message}
    end

    test "both implementations access the same fixed field", %{binary: binary} do
      require NativeBenchmarkCodec

      assert Native.benchmark_get_number(binary) == 42
      assert NativeBenchmarkCodec.get(binary, :number) == 42
    end
  end
end
