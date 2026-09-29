defmodule GridCodec.NativeTest do
  use ExUnit.Case, async: true

  alias GridCodec.Native
  alias GridCodec.Native.Header
  alias GridCodec.Native.Nif
  alias GridCodec.NativeBenchmarkCodec

  require NativeBenchmarkCodec

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
      assert Native.benchmark_get_number(binary) == 42
      assert NativeBenchmarkCodec.get(binary, :number) == 42
    end

    test "Elixir encode crosses Rustler into Rust, returns through Rustler, and Elixir decodes it",
         %{binary: elixir_binary, message: message} do
      {number, signed, active, name} = Native.benchmark_decode(elixir_binary)
      rust_binary = Native.benchmark_encode(number, signed, active, name)

      assert rust_binary == elixir_binary
      assert NativeBenchmarkCodec.decode(rust_binary) == {:ok, message}
    end

    test "Rust encode crosses Rustler into Elixir, returns through Rustler, and Rust decodes it",
         %{binary: elixir_binary, message: message} do
      rust_binary =
        Native.benchmark_encode(message.number, message.signed, message.active, message.name)

      assert {:ok, decoded_by_elixir} = NativeBenchmarkCodec.decode(rust_binary)
      assert {:ok, elixir_binary_after_roundtrip} = NativeBenchmarkCodec.encode(decoded_by_elixir)
      assert elixir_binary_after_roundtrip == elixir_binary
      assert Native.benchmark_decode(elixir_binary_after_roundtrip) == {42, -7, true, "grid"}
    end

    test "malformed binaries fail safely across the Rustler boundary and the NIF remains usable",
         %{binary: binary} do
      for length <- 0..(byte_size(binary) - 1) do
        truncated = binary_part(binary, 0, length)
        assert {:error, reason} = Native.benchmark_decode(truncated)
        assert is_binary(reason)
      end

      <<before_bool::binary-size(20), _bool, after_bool::binary>> = binary
      invalid_bool = <<before_bool::binary, 2, after_bool::binary>>
      assert {:error, "invalid boolean byte 2"} = Native.benchmark_decode(invalid_bool)

      <<before_name::binary-size(22), _name_byte, after_name::binary>> = binary
      invalid_utf8 = <<before_name::binary, 255, after_name::binary>>
      assert {:error, "invalid UTF-8"} = Native.benchmark_decode(invalid_utf8)

      assert Native.benchmark_decode(binary) == {42, -7, true, "grid"}
    end
  end
end
