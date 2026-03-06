defmodule GridCodec.Batch.PerTypeGroups do
  @moduledoc """
  Architecture C: Per-Type Groups + Sequence Index.

  One standard homogeneous group per type. Each entry gets a `seq_index::u32` field
  prepended. Original ordering is reconstructed via k-way merge on `seq_index`.
  Enables O(1) type-based filtering and parallel group decode.

  ## Wire Format

      ┌───────────────────────────────────────────────────────────┐
      │ Batch Header (2 bytes)                                    │
      │  numTypes (u8) | reserved (u8)                            │
      ├───────────────────────────────────────────────────────────┤
      │ TypeGroup[0] — standard Group wire format                 │
      │  ┌────────────────┬───────────────────────────────────┐  │
      │  │ entrySize (u16) │ numInGroup (u16 LE)              │  │
      │  ├────────────────┴───────────────────────────────────┤  │
      │  │ Entry: <<seq_index::u32, type_payload::binary>>    │  │
      │  │ Entry: ...                                         │  │
      │  └────────────────────────────────────────────────────┘  │
      ├───────────────────────────────────────────────────────────┤
      │ TypeGroup[1] ...                                          │
      └───────────────────────────────────────────────────────────┘

  Per-entry overhead: 4 bytes (seq_index only).
  Groups appear in type_specs order — the tag is implicit from group position.
  """

  @batch_header_size 2
  @group_header_size 4
  @seq_size 4

  defstruct [
    :binary,
    :num_types,
    :total_count,
    :type_specs,
    :groups,
    :module_to_tag
  ]

  @type type_spec ::
          {tag :: non_neg_integer(), module :: module(), block_length :: non_neg_integer()}

  @type group_info :: %{
          binary: binary(),
          count: non_neg_integer(),
          entry_size: non_neg_integer(),
          block_length: non_neg_integer()
        }

  @type t :: %__MODULE__{
          binary: binary(),
          num_types: non_neg_integer(),
          total_count: non_neg_integer(),
          type_specs: [type_spec()],
          groups: %{non_neg_integer() => group_info()},
          module_to_tag: %{module() => type_spec()}
        }

  @spec encode([struct()], [type_spec()]) :: {:ok, binary()} | {:error, term()}
  def encode(entries, type_specs) do
    module_to_spec = Map.new(type_specs, fn {_tag, mod, _bl} = spec -> {mod, spec} end)
    num_types = length(type_specs)

    empty_buckets = Map.new(type_specs, fn {tag, _, _} -> {tag, []} end)

    {classified, _seq} =
      Enum.map_reduce(entries, 0, fn entry, seq ->
        mod = entry.__struct__

        case Map.fetch(module_to_spec, mod) do
          {:ok, {tag, ^mod, _bl}} ->
            {{tag, seq, entry}, seq + 1}

          :error ->
            raise ArgumentError, "type #{inspect(mod)} not in any_of set"
        end
      end)

    buckets =
      Enum.reduce(classified, empty_buckets, fn {tag, seq, entry}, acc ->
        Map.update!(acc, tag, fn list -> [{seq, entry} | list] end)
      end)

    group_iodata =
      Enum.map(type_specs, fn {tag, mod, bl} ->
        entries_for_type = buckets |> Map.fetch!(tag) |> :lists.reverse()
        entry_size = @seq_size + bl
        num_in_group = length(entries_for_type)

        encoded =
          Enum.map(entries_for_type, fn {seq, entry} ->
            {:ok, payload} = mod.encode(entry, header: false)
            <<seq::little-32, payload::binary>>
          end)

        [<<entry_size::little-16, num_in_group::little-16>> | encoded]
      end)

    batch_header = <<num_types::8, 0::8>>
    {:ok, IO.iodata_to_binary([batch_header | group_iodata])}
  end

  @spec decode(binary(), [type_spec()]) :: {:ok, t()} | {:error, term()}
  def decode(binary, _type_specs) when byte_size(binary) < @batch_header_size do
    {:error, {:insufficient_data, byte_size(binary), @batch_header_size}}
  end

  def decode(<<num_types::8, _reserved::8, rest::binary>> = binary, type_specs) do
    {groups, _remaining} =
      Enum.reduce(type_specs, {%{}, rest}, fn {tag, _mod, bl}, {groups_acc, rest_bin} ->
        <<entry_size::little-16, num_in_group::little-16, data_and_rest::binary>> = rest_bin
        total_data = entry_size * num_in_group
        group_total = @group_header_size + total_data

        group_binary =
          binary_part(rest_bin, 0, group_total)

        remaining =
          binary_part(data_and_rest, total_data, byte_size(data_and_rest) - total_data)

        group = %{
          binary: group_binary,
          count: num_in_group,
          entry_size: entry_size,
          block_length: bl
        }

        {Map.put(groups_acc, tag, group), remaining}
      end)

    total_count = groups |> Map.values() |> Enum.map(& &1.count) |> Enum.sum()

    {:ok,
     %__MODULE__{
       binary: binary,
       num_types: num_types,
       total_count: total_count,
       type_specs: type_specs,
       groups: groups,
       module_to_tag: Map.new(type_specs, fn {_tag, mod, _bl} = spec -> {mod, spec} end)
     }}
  end

  @spec count(t()) :: non_neg_integer()
  def count(%__MODULE__{total_count: n}), do: n

  @spec get(t(), non_neg_integer()) ::
          {:ok, {non_neg_integer(), non_neg_integer(), map()}} | {:error, term()}
  def get(%__MODULE__{} = batch, target_seq)
      when target_seq < 0 or target_seq >= batch.total_count do
    {:error, {:index_out_of_bounds, target_seq, batch.total_count}}
  end

  def get(%__MODULE__{} = batch, target_seq) do
    Enum.find_value(batch.type_specs, {:error, :not_found}, fn {tag, mod, bl} ->
      group = Map.fetch!(batch.groups, tag)
      scan_group_for_seq(group, tag, mod, bl, target_seq)
    end)
  end

  @spec stream(t()) :: Enumerable.t()
  def stream(%__MODULE__{total_count: 0}), do: []

  def stream(%__MODULE__{} = batch) do
    cursors = init_cursors(batch)
    merge_by_seq(cursors)
  end

  @spec by_type(t(), non_neg_integer()) :: [map()]
  def by_type(%__MODULE__{} = batch, target_tag) do
    {^target_tag, mod, bl} = Enum.find(batch.type_specs, fn {t, _, _} -> t == target_tag end)
    group = Map.fetch!(batch.groups, target_tag)
    decode_group_entries(group, mod, bl)
  end

  @spec to_list(t()) :: [{non_neg_integer(), non_neg_integer(), map()}]
  def to_list(%__MODULE__{} = batch), do: Enum.to_list(stream(batch))

  @spec wire_size(binary()) :: non_neg_integer()
  def wire_size(binary) when is_binary(binary), do: byte_size(binary)

  # -- internals --

  defp scan_group_for_seq(group, tag, mod, bl, target_seq) do
    entry_size = group.entry_size

    Enum.find_value(0..(group.count - 1)//1, nil, fn i ->
      offset = @group_header_size + i * entry_size
      <<_::binary-size(offset), seq::little-32, _::binary>> = group.binary

      if seq == target_seq do
        payload = binary_part(group.binary, offset + @seq_size, bl)
        {:ok, decoded} = mod.decode(payload, header: false)
        {:ok, {seq, tag, decoded}}
      end
    end)
  end

  defp decode_group_entries(%{count: 0}, _mod, _bl), do: []

  defp decode_group_entries(group, mod, bl) do
    entry_size = group.entry_size

    Enum.map(0..(group.count - 1)//1, fn i ->
      offset = @group_header_size + i * entry_size + @seq_size
      payload = binary_part(group.binary, offset, bl)
      {:ok, decoded} = mod.decode(payload, header: false)
      decoded
    end)
  end

  # Lazy k-way merge: initialize one cursor per non-empty group
  defp init_cursors(batch) do
    Enum.flat_map(batch.type_specs, fn {tag, mod, bl} ->
      group = Map.fetch!(batch.groups, tag)

      if group.count > 0 do
        {seq, decoded} = decode_at(group, mod, bl, 0)
        [%{seq: seq, tag: tag, entry: decoded, pos: 0, group: group, mod: mod, bl: bl}]
      else
        []
      end
    end)
  end

  defp merge_by_seq(initial_cursors) do
    Stream.unfold(initial_cursors, fn
      [] ->
        nil

      cursors ->
        {min_cursor, min_idx} =
          cursors
          |> Enum.with_index()
          |> Enum.min_by(fn {c, _} -> c.seq end)

        result = {min_cursor.seq, min_cursor.tag, min_cursor.entry}
        next_pos = min_cursor.pos + 1

        updated =
          if next_pos < min_cursor.group.count do
            {next_seq, next_decoded} =
              decode_at(min_cursor.group, min_cursor.mod, min_cursor.bl, next_pos)

            List.replace_at(cursors, min_idx, %{
              min_cursor
              | seq: next_seq,
                entry: next_decoded,
                pos: next_pos
            })
          else
            List.delete_at(cursors, min_idx)
          end

        {result, updated}
    end)
  end

  defp decode_at(group, mod, bl, pos) do
    offset = @group_header_size + pos * group.entry_size
    <<_::binary-size(offset), seq::little-32, payload::binary-size(bl), _::binary>> = group.binary
    {:ok, decoded} = mod.decode(payload, header: false)
    {seq, decoded}
  end
end
