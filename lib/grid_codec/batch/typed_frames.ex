defmodule GridCodec.Batch.TypedFrames do
  @moduledoc """
  Typed Frames batch encoding strategy.

  Each entry is length-prefixed with a type tag. No padding, so wire size is minimal,
  but an offset index is built on decode for O(1) random access.

  ## Wire Format

      ┌───────────────────────────────────────────────────────────┐
      │ Batch Header (8 bytes)                                     │
      │  bodySize (u32 LE)  │  numEntries (u32 LE)                 │
      ├───────────────────────────────────────────────────────────┤
      │ Frame[0]                                                   │
      │  ┌──────────┬─────────┬────────────┬─────────────────────┐ │
      │  │ seq (u32) │ tag (u8)│ len (u16)  │ payload (len bytes) │ │
      │  └──────────┴─────────┴────────────┴─────────────────────┘ │
      ├───────────────────────────────────────────────────────────┤
      │ Frame[1] ...                                               │
      └───────────────────────────────────────────────────────────┘

  Per-frame overhead: 7 bytes (4 seq + 1 tag + 2 length).
  No padding waste. Offset index built on decode for O(1) random access.

  ## Tradeoffs vs Padded Union

  - **Smaller wire size** when types have different `block_length` values
  - **8-byte batch header** vs 4-byte Group header (one-time cost)
  - **Offset index allocation** on decode (tuple of integers, ~8 bytes per entry)
  - **Same O(1) random access** after decode via pre-built offsets
  """

  @batch_header_size 8
  @frame_header_size 7

  defstruct [
    :binary,
    :num_entries,
    :type_specs,
    :tag_to_spec,
    :frame_offsets
  ]

  @type type_spec ::
          {tag :: non_neg_integer(), module :: module(), block_length :: non_neg_integer()}

  @type t :: %__MODULE__{
          binary: binary(),
          num_entries: non_neg_integer(),
          type_specs: [type_spec()],
          tag_to_spec: %{non_neg_integer() => type_spec()},
          frame_offsets: tuple()
        }

  @doc """
  Encodes a list of structs into the typed frames binary format.

  Used by the standalone `TypedFrames` module. For DSL integration, the
  compiler generates inline encoder functions instead.
  """
  @spec encode([struct()], [type_spec()]) :: {:ok, binary()} | {:error, term()}
  def encode(entries, type_specs) do
    module_to_spec = Map.new(type_specs, fn {_tag, mod, _bl} = spec -> {mod, spec} end)

    {iodata, _seq} =
      Enum.map_reduce(entries, 0, fn entry, seq ->
        mod = entry.__struct__

        case Map.fetch(module_to_spec, mod) do
          {:ok, {tag, ^mod, _bl}} ->
            {:ok, payload} = mod.encode(entry, header: false)
            payload_length = byte_size(payload)
            frame = <<seq::little-32, tag::8, payload_length::little-16, payload::binary>>
            {frame, seq + 1}

          :error ->
            raise ArgumentError, "type #{inspect(mod)} not in any_of set"
        end
      end)

    num_entries = length(entries)
    frames_bin = IO.iodata_to_binary(iodata)
    body_size = 4 + byte_size(frames_bin)
    {:ok, <<body_size::little-32, num_entries::little-32, frames_bin::binary>>}
  end

  @doc """
  Decodes a typed frames binary into a `TypedFrames` struct.
  """
  @spec decode(binary(), [type_spec()]) :: {:ok, t()} | {:error, term()}
  def decode(binary, _type_specs) when byte_size(binary) < @batch_header_size do
    {:error, {:insufficient_data, byte_size(binary), @batch_header_size}}
  end

  def decode(<<body_size::little-32, num_entries::little-32, rest::binary>> = binary, type_specs) do
    frames_size = body_size - 4

    if byte_size(rest) < frames_size do
      {:error, {:insufficient_data, byte_size(rest), frames_size}}
    else
      case build_offsets(rest, num_entries, @batch_header_size, []) do
        {:ok, offsets} ->
          tag_to_spec = Map.new(type_specs, fn {tag, _mod, _bl} = spec -> {tag, spec} end)

          {:ok,
           %__MODULE__{
             binary: binary,
             num_entries: num_entries,
             type_specs: type_specs,
             tag_to_spec: tag_to_spec,
             frame_offsets: List.to_tuple(offsets)
           }}

        {:error, _} = err ->
          err
      end
    end
  end

  @doc """
  Parses a typed frames section from a larger binary and returns `{batch, rest}`.

  Used by the compiler-generated decoder to extract the batch from the parent
  codec's binary. Raises on malformed data (trusted binary format).
  """
  @spec parse_with_rest!(binary(), [type_spec()]) :: {t(), binary()}
  def parse_with_rest!(binary, _type_specs) when byte_size(binary) < @batch_header_size do
    raise ArgumentError,
          "TypedFrames binary too short: #{byte_size(binary)} bytes, need #{@batch_header_size}"
  end

  def parse_with_rest!(
        <<body_size::little-32, _num_entries::little-32, _::binary>> = binary,
        type_specs
      ) do
    total_section = 4 + body_size

    if byte_size(binary) < total_section do
      raise ArgumentError,
            "TypedFrames data truncated: need #{total_section} bytes, have #{byte_size(binary)}"
    end

    section_bin = binary_part(binary, 0, total_section)
    rest = binary_part(binary, total_section, byte_size(binary) - total_section)

    case decode(section_bin, type_specs) do
      {:ok, tf} -> {tf, rest}
      {:error, reason} -> raise ArgumentError, "Failed to decode typed frames: #{inspect(reason)}"
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
    offset = elem(batch.frame_offsets, index)

    <<_::binary-size(offset), seq::little-32, tag::8, payload_length::little-16,
      payload::binary-size(payload_length), _::binary>> = batch.binary

    {^tag, mod, _bl} = Map.fetch!(batch.tag_to_spec, tag)
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
    {^target_tag, mod, _bl} = Map.fetch!(batch.tag_to_spec, target_tag)

    Enum.reduce((batch.num_entries - 1)..0//-1, [], fn i, acc ->
      frame_offset = elem(batch.frame_offsets, i)

      <<_::binary-size(frame_offset), _seq::little-32, tag::8, payload_length::little-16,
        payload::binary-size(payload_length), _::binary>> = batch.binary

      if tag == target_tag do
        {:ok, decoded} = mod.decode(payload, header: false)
        [decoded | acc]
      else
        acc
      end
    end)
  end

  @spec to_list(t()) :: [{non_neg_integer(), non_neg_integer(), map()}]
  def to_list(%__MODULE__{} = batch), do: Enum.to_list(stream(batch))

  @spec wire_size(t() | binary()) :: non_neg_integer()
  def wire_size(%__MODULE__{binary: binary}), do: byte_size(binary)
  def wire_size(binary) when is_binary(binary), do: byte_size(binary)

  defp build_offsets(_rest, 0, _current, acc), do: {:ok, :lists.reverse(acc)}

  defp build_offsets(
         <<_seq::little-32, _tag::8, payload_length::little-16,
           _payload::binary-size(payload_length), rest::binary>>,
         remaining,
         current,
         acc
       ) do
    frame_size = @frame_header_size + payload_length
    build_offsets(rest, remaining - 1, current + frame_size, [current | acc])
  end

  defp build_offsets(_rest, _remaining, _current, _acc) do
    {:error, :truncated_frame}
  end
end
