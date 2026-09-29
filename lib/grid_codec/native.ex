defmodule GridCodec.Native do
  @moduledoc """
  Experimental Rust-backed GridCodec operations.

  This module is intentionally opt-in. Generated Elixir encoders, decoders, and
  field-access macros remain the default because small NIF calls can cost more
  than the work they replace. The native path is for parity experiments and
  larger batch operations where profiling demonstrates a gain.
  """

  alias GridCodec.Native.Nif

  @spec read_header(binary()) :: GridCodec.Native.Header.t()
  def read_header(binary), do: Nif.read_header(binary)

  @spec benchmark_get_number(binary()) :: non_neg_integer()
  def benchmark_get_number(binary), do: Nif.benchmark_get_number(binary)

  @spec benchmark_encode(non_neg_integer(), integer(), boolean(), String.t()) :: binary()
  def benchmark_encode(number, signed, active, name),
    do: Nif.benchmark_encode(number, signed, active, name)

  @spec benchmark_decode(binary()) :: {non_neg_integer(), integer(), boolean(), String.t()}
  def benchmark_decode(binary), do: Nif.benchmark_decode(binary)

  @spec encode_primitives(non_neg_integer(), integer(), boolean(), String.t()) :: binary()
  def encode_primitives(number, signed, active, name),
    do: Nif.encode_primitives(number, signed, active, name)

  @spec decode_primitives(binary()) :: {non_neg_integer(), integer(), boolean(), String.t()}
  def decode_primitives(binary), do: Nif.decode_primitives(binary)
end
