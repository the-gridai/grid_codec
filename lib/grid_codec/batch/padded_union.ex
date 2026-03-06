defmodule GridCodec.Batch.PaddedUnion do
  @moduledoc """
  Padded Union Group — the default batch encoding strategy.

  Each entry is padded to `max(block_lengths)` across all types in the `any_of` set,
  yielding fixed-size entries that enable O(1) random access. Reuses the same wire
  format as `GridCodec.Group` (u16 blockLength + u16 numInGroup header).

  This is the default strategy for `batch/2`. For varied-size types where wire
  size matters, see `GridCodec.Batch.TypedFrames` (`:typed_frames` strategy).

  ## Wire Format

      ┌───────────────────────────────────────────────────────────┐
      │ Header (4 bytes)                                          │
      │ ┌─────────────────────┬─────────────────────────────────┐ │
      │ │ envelopeSize (u16)  │  numEntries (u16 LE)            │ │
      │ └─────────────────────┴─────────────────────────────────┘ │
      ├───────────────────────────────────────────────────────────┤
      │ Entry[0] (envelopeSize bytes)                             │
      │  ┌──────────┬─────────┬────────────────────┬───────────┐ │
      │  │ seq (u32) │ tag (u8)│ payload (bl bytes) │ padding   │ │
      │  └──────────┴─────────┴────────────────────┴───────────┘ │
      ├───────────────────────────────────────────────────────────┤
      │ Entry[1] ...                                              │
      └───────────────────────────────────────────────────────────┘

  Envelope overhead per entry: 5 bytes (4 seq + 1 tag).
  Padding per entry: `max_block_length - entry_block_length` zero bytes.
  """

  @header_size 4
  @seq_size 4
  @tag_size 1
  @envelope_overhead @seq_size + @tag_size

  defstruct [
    :binary,
    :num_entries,
    :envelope_size,
    :max_block_length,
    :type_specs,
    :tag_to_spec
  ]

  @type type_spec ::
          {tag :: non_neg_integer(), module :: module(), block_length :: non_neg_integer()}

  @type t :: %__MODULE__{
          binary: binary(),
          num_entries: non_neg_integer(),
          envelope_size: non_neg_integer(),
          max_block_length: non_neg_integer(),
          type_specs: [type_spec()],
          tag_to_spec: %{non_neg_integer() => type_spec()}
        }

  @spec encode([struct()], [type_spec()]) :: {:ok, binary()} | {:error, term()}
  def encode(entries, type_specs) do
    module_to_spec = Map.new(type_specs, fn {_tag, mod, _bl} = spec -> {mod, spec} end)
    max_bl = type_specs |> Enum.map(fn {_, _, bl} -> bl end) |> Enum.max(fn -> 0 end)
    envelope_size = @envelope_overhead + max_bl

    {iodata, _seq} =
      Enum.map_reduce(entries, 0, fn entry, seq ->
        mod = entry.__struct__

        case Map.fetch(module_to_spec, mod) do
          {:ok, {tag, ^mod, bl}} ->
            {:ok, payload} = mod.encode(entry, header: false)
            padding_size = max_bl - bl
            frame = <<seq::little-32, tag::8, payload::binary, 0::size(padding_size)-unit(8)>>
            {frame, seq + 1}

          :error ->
            raise ArgumentError, "type #{inspect(mod)} not in any_of set"
        end
      end)

    num_entries = length(entries)
    header = <<envelope_size::little-16, num_entries::little-16>>
    {:ok, IO.iodata_to_binary([header | iodata])}
  end

  @spec decode(binary(), [type_spec()]) :: {:ok, t()} | {:error, term()}
  def decode(binary, _type_specs) when byte_size(binary) < @header_size do
    {:error, {:insufficient_data, byte_size(binary), @header_size}}
  end

  def decode(
        <<envelope_size::little-16, num_entries::little-16, _rest::binary>> = binary,
        type_specs
      ) do
    max_bl = envelope_size - @envelope_overhead
    expected_size = @header_size + num_entries * envelope_size

    if byte_size(binary) < expected_size do
      {:error, {:insufficient_data, byte_size(binary), expected_size}}
    else
      tag_to_spec = Map.new(type_specs, fn {tag, _mod, _bl} = spec -> {tag, spec} end)

      {:ok,
       %__MODULE__{
         binary: binary,
         num_entries: num_entries,
         envelope_size: envelope_size,
         max_block_length: max_bl,
         type_specs: type_specs,
         tag_to_spec: tag_to_spec
       }}
    end
  end

  @spec count(t()) :: non_neg_integer()
  def count(%__MODULE__{num_entries: n}), do: n

  @spec get(t(), non_neg_integer()) ::
          {:ok, {non_neg_integer(), non_neg_integer(), map()}} | {:error, term()}
  def get(%__MODULE__{num_entries: n}, index) when index < 0 or index >= n do
    {:error, {:index_out_of_bounds, index, n}}
  end

  def get(%__MODULE__{} = batch, index) do
    offset = @header_size + index * batch.envelope_size
    entry_bin = binary_part(batch.binary, offset, batch.envelope_size)
    <<seq::little-32, tag::8, payload_and_padding::binary>> = entry_bin
    {^tag, mod, bl} = Map.fetch!(batch.tag_to_spec, tag)
    payload = binary_part(payload_and_padding, 0, bl)
    {:ok, decoded} = mod.decode(payload, header: false)
    {:ok, {seq, tag, decoded}}
  end

  @spec stream(t()) :: Enumerable.t()
  def stream(%__MODULE__{num_entries: 0}), do: []

  def stream(%__MODULE__{} = batch) do
    Stream.unfold(0, fn
      i when i >= batch.num_entries ->
        nil

      i ->
        {:ok, entry} = get(batch, i)
        {entry, i + 1}
    end)
  end

  @spec by_type(t(), non_neg_integer()) :: [map()]
  def by_type(%__MODULE__{} = batch, target_tag) do
    {^target_tag, mod, bl} = Map.fetch!(batch.tag_to_spec, target_tag)

    Enum.reduce((batch.num_entries - 1)..0//-1, [], fn i, acc ->
      offset = @header_size + i * batch.envelope_size + @seq_size
      <<_::binary-size(offset), tag::8, _::binary>> = batch.binary

      if tag == target_tag do
        payload_offset = offset + @tag_size
        payload = binary_part(batch.binary, payload_offset, bl)
        {:ok, decoded} = mod.decode(payload, header: false)
        [decoded | acc]
      else
        acc
      end
    end)
  end

  @spec to_list(t()) :: [{non_neg_integer(), non_neg_integer(), map()}]
  def to_list(%__MODULE__{} = batch), do: Enum.to_list(stream(batch))

  @spec wire_size(binary()) :: non_neg_integer()
  def wire_size(binary) when is_binary(binary), do: byte_size(binary)
end
