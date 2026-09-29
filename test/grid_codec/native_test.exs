defmodule GridCodec.NativeTest do
  use ExUnit.Case, async: true

  alias GridCodec.Native
  alias GridCodec.Native.Header
  alias GridCodec.Native.Nif

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
end
