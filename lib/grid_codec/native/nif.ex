defmodule GridCodec.Native.Nif do
  @moduledoc false

  use Rustler, otp_app: :grid_codec, crate: "grid_codec_nif"

  def read_header(_binary), do: :erlang.nif_error(:nif_not_loaded)

  def benchmark_get_number(_binary), do: :erlang.nif_error(:nif_not_loaded)

  def benchmark_encode(_number, _signed, _active, _name),
    do: :erlang.nif_error(:nif_not_loaded)

  def benchmark_decode(_binary), do: :erlang.nif_error(:nif_not_loaded)

  def encode_primitives(_number, _signed, _active, _name),
    do: :erlang.nif_error(:nif_not_loaded)

  def decode_primitives(_binary), do: :erlang.nif_error(:nif_not_loaded)
end
