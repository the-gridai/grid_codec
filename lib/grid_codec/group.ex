defmodule GridCodec.Group do
  @moduledoc """
  Repeating groups for arrays of entries.

  Groups encode variable-length arrays where each entry has the same
  structure. Three group styles are supported:

  | Style | DSL | Wire Format | Decode |
  |-------|-----|-------------|--------|
  | Fixed | `group :g do ... end` or `group :g, of: M` | blockLength/numInGroup header, uniform entries | Lazy `%Group{}` with O(1) random access |
  | Framed | `group :g, of: M, framing: :length_prefixed` | numEntries (u32) + length-prefixed payloads | Eager list |
  | Scalar | `group :g, of: :uuid` | Fixed or framed depending on type | Eager list |

  ## Fixed Group Wire Format

      ┌─────────────────────────────────────────────────────────┐
      │ Group Header (4 bytes)                                  │
      │ ┌────────────────────┬────────────────────────────────┐ │
      │ │ blockLength (u16)  │  numInGroup (u16 LE)           │ │
      │ └────────────────────┴────────────────────────────────┘ │
      ├─────────────────────────────────────────────────────────┤
      │ Entry[0] (blockLength bytes)                            │
      ├─────────────────────────────────────────────────────────┤
      │ Entry[1] (blockLength bytes)                            │
      ├─────────────────────────────────────────────────────────┤
      │ ...                                                     │
      ├─────────────────────────────────────────────────────────┤
      │ Entry[N-1] (blockLength bytes)                          │
      └─────────────────────────────────────────────────────────┘

  Header: `blockLength` (u16 LE) + `numInGroup` (u16 LE).
  Entries must be fixed-size only (no variable-length fields).

  ## Framed Group Wire Format

      ┌─────────────────────────────────────────────────────────┐
      │ numEntries (u32 LE)                                     │
      ├─────────────────────────────────────────────────────────┤
      │ payloadLen[0] (u16 LE) │ payload[0]                    │
      ├─────────────────────────────────────────────────────────┤
      │ payloadLen[1] (u16 LE) │ payload[1]                    │
      ├─────────────────────────────────────────────────────────┤
      │ ...                                                     │
      └─────────────────────────────────────────────────────────┘

  Each entry is length-prefixed, allowing variable-length payloads.
  Entries are eagerly decoded to a plain list (no lazy `%Group{}`).

  ## Scalar Group Wire Format

  Scalar groups store homogeneous lists of single values (UUIDs,
  integers, strings). Fixed-size scalars use the fixed group wire
  format; variable-length scalars auto-select framed encoding.
  Both eagerly decode to a plain list.

  ## Zero-Copy Access (Fixed Groups)

  Fixed groups support O(1) random access to any entry:

      {:ok, group} = GridCodec.Group.parse(binary, entry_decoder)

      # Get count without iteration
      count = GridCodec.Group.count(group)

      # Direct access to entry at index
      {:ok, entry} = GridCodec.Group.get_entry(group, 42)

      # Access field within entry at index
      {:ok, price} = GridCodec.Group.get_field(group, 42, :price)

  ## Lazy Iteration (Fixed Groups)

  Fixed groups are lazy — entries are only decoded when accessed:

      group
      |> GridCodec.Group.stream()
      |> Stream.filter(fn entry -> entry.price > 100 end)
      |> Enum.take(10)

  ## Security Limits

  To prevent memory exhaustion from malformed data:

  - Default max entries: 65,535 (u16 max)
  - Default max total bytes: 8MB

  Configure via options:

      GridCodec.Group.parse(binary, decoder,
        max_entries: 10_000,
        max_bytes: 1_000_000
      )

  ## Usage Examples

  ### Fixed group (inline fields)

      defcodec do
        group :bids do
          field :price, :u64
          field :quantity, :u32
        end
      end

  ### Framed group (variable-length entries)

      defcodec do
        group :bills, of: Bill, framing: :length_prefixed
      end

  ### Scalar group

      defcodec do
        group :tag_ids, of: :uuid
        group :labels, of: :string16
      end
  """

  @header_size 4
  @max_u16 65_535
  @default_max_entries @max_u16
  @default_max_bytes 8 * 1024 * 1024

  @type t :: %__MODULE__{
          binary: binary(),
          num_in_group: non_neg_integer(),
          block_length: non_neg_integer(),
          entries_offset: non_neg_integer(),
          entry_decoder: (binary() -> {:ok, map()} | {:error, term()}),
          batch_decoder: (binary(), [map()] -> [map()]) | nil,
          current_block_length: non_neg_integer() | nil,
          null_block: binary() | nil
        }

  defstruct [
    :binary,
    :num_in_group,
    :block_length,
    :entries_offset,
    :entry_decoder,
    :batch_decoder,
    # Version-aware decoding (fixed groups only). When an older writer produced
    # shorter entries than the current entry layout, `block_length` (read from
    # the wire header) is the *writer's* entry size and `current_block_length`
    # is the reader's. Each entry is padded from `null_block` up to
    # `current_block_length` before decoding. Both are `nil` for paths that do
    # not participate in entry version padding (framed/scalar groups, batches,
    # and the public `parse/3` API), which keeps the fast path allocation-free.
    :current_block_length,
    :null_block
  ]

  # ============================================================================
  # Encoding
  # ============================================================================

  @doc """
  Encodes a list of entries into group format.

  Each entry is encoded using the provided encoder function, which must
  return a fixed-size binary.

  ## Security

  This function validates:
  - Entry count doesn't exceed u16 max (65,535)
  - Entry size doesn't exceed u16 max (65,535 bytes)
  - All entries have consistent size

  ## Limits

  - Max entries: 65,535 (u16)
  - Max entry size: 65,535 bytes (u16)

  ## Example

      entries = [%{price: 100, qty: 10}, %{price: 99, qty: 20}]
      binary = GridCodec.Group.encode(entries, fn entry ->
        <<entry.price::little-64, entry.qty::little-32>>
      end)
  """
  @spec encode(list(), (term() -> binary())) :: binary()
  def encode(entries, entry_encoder) when is_list(entries) and is_function(entry_encoder, 1) do
    num_entries = length(entries)

    # Security: Validate entry count fits in u16
    if num_entries > @max_u16 do
      raise ArgumentError, "Group entry count #{num_entries} exceeds u16 max (#{@max_u16})"
    end

    case entries do
      [] ->
        # Empty group: header with 0 block_length and 0 count
        <<0::little-16, 0::little-16>>

      [first | _] ->
        first_encoded = entry_encoder.(first)
        block_length = byte_size(first_encoded)

        # Security: Validate entry size fits in u16
        if block_length > @max_u16 do
          raise ArgumentError, "Entry size #{block_length} exceeds u16 max (#{@max_u16})"
        end

        # Security: Validate total data won't overflow
        total_size = num_entries * block_length

        if total_size > @default_max_bytes do
          raise ArgumentError,
                "Total group size #{total_size} exceeds max_bytes limit (#{@default_max_bytes})"
        end

        encoded_entries =
          Enum.map(entries, fn entry ->
            encoded = entry_encoder.(entry)

            # Security: Validate consistent entry size
            if byte_size(encoded) != block_length do
              raise ArgumentError,
                    "All group entries must have same size. Expected #{block_length}, got #{byte_size(encoded)}"
            end

            encoded
          end)

        # Header order: blockLength, numInGroup
        header = <<block_length::little-16, num_entries::little-16>>
        IO.iodata_to_binary([header | encoded_entries])
    end
  end

  @doc """
  Fast encoding for auto-generated groups where block_length is known at compile time.

  Skips per-entry size validation and first-entry double-encoding.
  Uses single-pass count+encode via `:lists.mapfoldl`.
  """
  @spec encode_fast(list(), (term() -> binary()), pos_integer()) :: binary()
  def encode_fast([], _entry_encoder, _block_length) do
    <<0::little-16, 0::little-16>>
  end

  def encode_fast(entries, entry_encoder, block_length)
      when is_list(entries) and is_function(entry_encoder, 1) do
    {encoded, count} =
      :lists.mapfoldl(fn entry, n -> {entry_encoder.(entry), n + 1} end, 0, entries)

    :erlang.iolist_to_binary([<<block_length::little-16, count::little-16>> | encoded])
  end

  # ============================================================================
  # Framed (length-prefixed) encoding for variable-length entries
  # ============================================================================

  @doc """
  Encodes a list of entries using length-prefixed framing.

  Each entry is encoded via `entry_encoder`, then wrapped with a u16 LE length
  prefix. The header is a u32 LE entry count.

  Wire format:

      numEntries (u32 LE) | [payload_length (u16 LE) | payload]*

  ## Limits

  - Max entries: 4,294,967,295 (u32)
  - Max per-entry payload: 65,535 bytes (u16)
  """
  @spec encode_framed(list(), (term() -> binary())) :: binary()
  def encode_framed([], _entry_encoder) do
    <<0::little-32>>
  end

  def encode_framed(entries, entry_encoder)
      when is_list(entries) and is_function(entry_encoder, 1) do
    count = length(entries)

    frames =
      Enum.map(entries, fn entry ->
        payload = entry_encoder.(entry)
        payload_len = byte_size(payload)

        if payload_len > @max_u16 do
          raise ArgumentError,
                "Framed group entry payload #{payload_len} bytes exceeds u16 max (#{@max_u16})"
        end

        <<payload_len::little-16, payload::binary>>
      end)

    :erlang.iolist_to_binary([<<count::little-32>> | frames])
  end

  @doc """
  Parses a framed (length-prefixed) group and returns `{entries_list, rest_binary}`.

  Eagerly decodes all entries into a list. Used for variable-length group entries
  where O(1) random access is not applicable.

  Raises on malformed data.
  """
  @spec parse_framed_with_rest!(binary(), (binary() -> {:ok, map()} | {:error, term()})) ::
          {list(), binary()}
  def parse_framed_with_rest!(<<num_entries::little-32, rest::binary>>, entry_decoder) do
    decode_framed_entries(rest, num_entries, entry_decoder, [])
  end

  def parse_framed_with_rest!(binary, _entry_decoder) do
    raise ArgumentError,
          "Framed group binary too short: #{byte_size(binary)} bytes, need at least 4"
  end

  defp decode_framed_entries(rest, 0, _decoder, acc) do
    {:lists.reverse(acc), rest}
  end

  defp decode_framed_entries(
         <<payload_len::little-16, payload::binary-size(payload_len), rest::binary>>,
         remaining,
         decoder,
         acc
       ) do
    {:ok, entry} = decoder.(payload)
    decode_framed_entries(rest, remaining - 1, decoder, [entry | acc])
  end

  defp decode_framed_entries(rest, remaining, _decoder, _acc) do
    raise ArgumentError,
          "Insufficient framed group data: #{remaining} entries remaining, #{byte_size(rest)} bytes left"
  end

  @doc """
  Parses a fixed-size scalar group eagerly into a list and returns `{list, rest}`.

  Uses the standard group header (blockLength u16, numInGroup u16), then eagerly
  decodes all entries via the batch_decoder, returning a plain list of values.
  """
  @spec parse_scalar_fixed_with_rest!(binary(), term(), (binary(), list() -> list())) ::
          {list(), binary()}
  def parse_scalar_fixed_with_rest!(
        <<block_length::little-16, num_in_group::little-16, rest::binary>>,
        _entry_decoder,
        batch_decoder
      ) do
    total_data = num_in_group * block_length

    if byte_size(rest) < total_data do
      raise ArgumentError,
            "Insufficient scalar group data: need #{total_data} bytes, have #{byte_size(rest)}"
    end

    <<entries_bin::binary-size(^total_data), group_rest::binary>> = rest
    entries = batch_decoder.(entries_bin, [])
    {entries, group_rest}
  end

  def parse_scalar_fixed_with_rest!(binary, _entry_decoder, _batch_decoder) do
    raise ArgumentError,
          "Scalar group binary too short: #{byte_size(binary)} bytes, need at least 4"
  end

  # ============================================================================
  # Parsing
  # ============================================================================

  @doc """
  Parses a group from binary data.

  Returns a lazy group struct that can be iterated or randomly accessed.
  The actual entries are not decoded until accessed.

  ## Options

  - `:max_entries` - Maximum allowed entry count (default: #{@default_max_entries})
  - `:max_bytes` - Maximum total bytes for group (default: #{@default_max_bytes})

  ## Examples

      # With a decoder function
      {:ok, group} = GridCodec.Group.parse(binary, fn entry_binary ->
        <<price::little-64, qty::little-32>> = entry_binary
        {:ok, %{price: price, qty: qty}}
      end)

      # Check count
      count = GridCodec.Group.count(group)

      # Access entry
      {:ok, entry} = GridCodec.Group.get_entry(group, 0)
  """
  @spec parse(binary(), (binary() -> {:ok, map()} | {:error, term()}), keyword()) ::
          {:ok, t()} | {:error, term()}
  def parse(binary, entry_decoder, opts \\ [])

  # Guard: fast rejection of undersized binaries (O(1) check)
  def parse(binary, _entry_decoder, _opts) when byte_size(binary) < @header_size do
    {:error, {:insufficient_header, byte_size(binary), @header_size}}
  end

  def parse(
        <<block_length::little-16, num_in_group::little-16, rest::binary>> = binary,
        entry_decoder,
        opts
      ) do
    max_entries = Keyword.get(opts, :max_entries, @default_max_entries)
    max_bytes = Keyword.get(opts, :max_bytes, @default_max_bytes)
    total_data_size = num_in_group * block_length
    rest_size = byte_size(rest)

    # Security checks - structured for clarity, guards used where applicable
    cond do
      block_length == 0 and num_in_group > 0 ->
        {:error, {:invalid_block_length, block_length, num_in_group}}

      num_in_group > max_entries ->
        {:error, {:max_entries_exceeded, num_in_group, max_entries}}

      total_data_size > max_bytes ->
        {:error, {:max_bytes_exceeded, total_data_size, max_bytes}}

      rest_size < total_data_size ->
        {:error, {:insufficient_data, rest_size, total_data_size}}

      true ->
        {:ok,
         %__MODULE__{
           binary: binary,
           num_in_group: num_in_group,
           block_length: block_length,
           entries_offset: @header_size,
           entry_decoder: entry_decoder
         }}
    end
  end

  @doc """
  Pads a wire entry of `wire_bl` bytes up to `current_bl` using `null_block`,
  returning an entry binary ready for the current entry decoder.

  Version-aware group decoding: when an older writer emitted shorter entries
  (because the entry struct gained appended `:optional`/defaulted fields since),
  the per-group header records the *writer's* entry size (`wire_bl`). Each entry
  is padded up to the reader's current entry size (`current_bl`) with the entry's
  null-sentinel block so appended fields resolve to `nil`/default.

  Zero-cost fast path when `wire_bl >= current_bl` (the common same-version case):
  the original binary is returned unchanged with no allocation.
  """
  @spec pad_entry(binary(), non_neg_integer(), non_neg_integer(), binary()) :: binary()
  def pad_entry(entry, wire_bl, current_bl, _null_block) when wire_bl >= current_bl, do: entry

  def pad_entry(entry, wire_bl, current_bl, null_block) do
    padding = binary_part(null_block, wire_bl, current_bl - wire_bl)
    <<entry::binary, padding::binary>>
  end

  @doc """
  Parses a group and returns `{group, rest_binary}` in one call.

  Raises on malformed data. Used by auto-generated decoders where the
  binary format is trusted.
  """
  @spec parse_with_rest!(binary(), (binary() -> {:ok, map()} | {:error, term()})) ::
          {t(), binary()}
  def parse_with_rest!(binary, _entry_decoder) when byte_size(binary) < @header_size do
    raise ArgumentError,
          "Group binary too short: #{byte_size(binary)} bytes, need #{@header_size}"
  end

  def parse_with_rest!(
        <<block_length::little-16, num_in_group::little-16, rest::binary>> = binary,
        entry_decoder
      ) do
    parse_with_rest!(binary, block_length, num_in_group, rest, entry_decoder, nil)
  end

  @doc """
  Like `parse_with_rest!/2` but also stores a batch decoder for fast `to_list`.

  The batch decoder is a `(binary, acc) -> [map()]` function that decodes
  all entries in a single pass without per-entry sub-binary allocation.
  """
  @spec parse_with_rest!(
          binary(),
          (binary() -> {:ok, map()} | {:error, term()}),
          (binary(), [map()] -> [map()])
        ) :: {t(), binary()}
  def parse_with_rest!(binary, _entry_decoder, _batch_decoder)
      when byte_size(binary) < @header_size do
    raise ArgumentError,
          "Group binary too short: #{byte_size(binary)} bytes, need #{@header_size}"
  end

  def parse_with_rest!(
        <<block_length::little-16, num_in_group::little-16, rest::binary>> = binary,
        entry_decoder,
        batch_decoder
      ) do
    parse_with_rest!(binary, block_length, num_in_group, rest, entry_decoder, batch_decoder)
  end

  @doc """
  Like `parse_with_rest!/3` but version-aware for fixed group entries.

  `current_block_length` is the reader's current entry size and `null_block` is
  the entry's null-sentinel block (`current_block_length` bytes). When the wire
  header reports a smaller entry size than `current_block_length` (older writer),
  each entry is padded up to the current size before decoding so appended
  `:optional`/defaulted entry fields resolve to `nil`/default.

  Fast path: when the wire `block_length` already matches (or exceeds) the
  current size, behavior is byte-for-byte identical to `parse_with_rest!/3` and
  no padding is allocated.
  """
  @spec parse_with_rest!(
          binary(),
          (binary() -> {:ok, map()} | {:error, term()}),
          (binary(), [map()] -> [map()]),
          non_neg_integer(),
          binary()
        ) :: {t(), binary()}
  def parse_with_rest!(binary, _entry_decoder, _batch_decoder, _current_bl, _null_block)
      when byte_size(binary) < @header_size do
    raise ArgumentError,
          "Group binary too short: #{byte_size(binary)} bytes, need #{@header_size}"
  end

  def parse_with_rest!(
        <<block_length::little-16, num_in_group::little-16, rest::binary>> = binary,
        entry_decoder,
        batch_decoder,
        current_bl,
        null_block
      ) do
    parse_with_rest!(
      binary,
      block_length,
      num_in_group,
      rest,
      entry_decoder,
      batch_decoder,
      current_bl,
      null_block
    )
  end

  defp parse_with_rest!(binary, block_length, num_in_group, rest, entry_decoder, batch_decoder) do
    parse_with_rest!(
      binary,
      block_length,
      num_in_group,
      rest,
      entry_decoder,
      batch_decoder,
      nil,
      nil
    )
  end

  defp parse_with_rest!(
         binary,
         block_length,
         num_in_group,
         rest,
         entry_decoder,
         batch_decoder,
         current_bl,
         null_block
       ) do
    total_data = num_in_group * block_length

    if byte_size(rest) < total_data do
      raise ArgumentError,
            "Insufficient group data: need #{total_data} bytes, have #{byte_size(rest)}"
    end

    group = %__MODULE__{
      binary: binary,
      num_in_group: num_in_group,
      block_length: block_length,
      entries_offset: @header_size,
      entry_decoder: entry_decoder,
      batch_decoder: batch_decoder,
      current_block_length: current_bl,
      null_block: null_block
    }

    group_rest = binary_part(rest, total_data, byte_size(rest) - total_data)
    {group, group_rest}
  end

  @doc """
  Returns the number of entries in the group.

  O(1) operation - reads directly from header.
  """
  @spec count(t()) :: non_neg_integer()
  def count(%__MODULE__{num_in_group: n}), do: n

  @doc """
  Returns the block length (entry size) in bytes.
  """
  @spec block_length(t()) :: non_neg_integer()
  def block_length(%__MODULE__{block_length: bl}), do: bl

  @doc """
  Gets an entry at the given index.

  O(1) access - uses sub-binary reference for zero-copy.

  ## Example

      {:ok, entry} = GridCodec.Group.get_entry(group, 0)
  """
  @spec get_entry(t(), non_neg_integer()) :: {:ok, term()} | {:error, term()}
  def get_entry(%__MODULE__{num_in_group: n}, index) when index < 0 or index >= n do
    {:error, {:index_out_of_bounds, index, n}}
  end

  def get_entry(%__MODULE__{block_length: 0, num_in_group: n}, _index) when n > 0 do
    {:error, {:invalid_block_length, 0, n}}
  end

  def get_entry(
        %__MODULE__{
          binary: binary,
          block_length: block_length,
          entries_offset: offset,
          entry_decoder: decoder,
          current_block_length: current_bl,
          null_block: null_block
        },
        index
      ) do
    entry_offset = offset + index * block_length

    if entry_offset + block_length > byte_size(binary) do
      {:error, {:entry_out_of_bounds, index, entry_offset, block_length, byte_size(binary)}}
    else
      entry_binary = binary_part(binary, entry_offset, block_length)

      entry_binary =
        if is_integer(current_bl) and current_bl > block_length do
          pad_entry(entry_binary, block_length, current_bl, null_block)
        else
          entry_binary
        end

      decoder.(entry_binary)
    end
  end

  @doc """
  Gets a specific field from an entry at the given index.

  If the decoder returns a map, you can extract fields directly.
  """
  @spec get_field(t(), non_neg_integer(), atom()) :: {:ok, term()} | {:error, term()}
  def get_field(group, index, field_name) do
    case get_entry(group, index) do
      {:ok, entry} when is_map(entry) ->
        case Map.fetch(entry, field_name) do
          {:ok, value} -> {:ok, value}
          :error -> {:error, {:unknown_field, field_name}}
        end

      {:ok, _other} ->
        {:error, :entry_not_a_map}

      {:error, _} = error ->
        error
    end
  end

  # ============================================================================
  # Iteration
  # ============================================================================

  @doc """
  Returns a lazy Stream over the group entries.

  Entries are decoded on-demand as the stream is consumed.

  ## Example

      group
      |> GridCodec.Group.stream()
      |> Stream.filter(fn entry -> entry.price > 100 end)
      |> Enum.take(10)
  """
  @spec stream(t()) :: Enumerable.t()
  def stream(%__MODULE__{num_in_group: 0}), do: []

  def stream(%__MODULE__{num_in_group: n} = group) do
    Stream.map(0..(n - 1), fn index ->
      case get_entry(group, index) do
        {:ok, entry} -> entry
        {:error, reason} -> raise "Failed to decode entry #{index}: #{inspect(reason)}"
      end
    end)
  end

  @doc """
  Reduces over group entries, decoding each lazily.

  ## Example

      GridCodec.Group.reduce(group, 0, fn entry, acc ->
        acc + entry.quantity
      end)
  """
  @spec reduce(t(), acc, (map(), acc -> acc)) :: acc when acc: term()
  def reduce(%__MODULE__{num_in_group: 0}, acc, _fun), do: acc

  def reduce(%__MODULE__{num_in_group: n} = group, acc, fun) when is_function(fun, 2) do
    Enum.reduce(0..(n - 1), acc, fn index, acc ->
      {:ok, entry} = get_entry(group, index)
      fun.(entry, acc)
    end)
  end

  @doc """
  Maps a function over group entries.

  ## Example

      prices = GridCodec.Group.map(group, fn entry -> entry.price end)
  """
  @spec map(t(), (map() -> term())) :: [term()]
  def map(%__MODULE__{num_in_group: 0}, _fun), do: []

  def map(%__MODULE__{num_in_group: n} = group, fun) when is_function(fun, 1) do
    Enum.map(0..(n - 1), fn index ->
      {:ok, entry} = get_entry(group, index)
      fun.(entry)
    end)
  end

  @doc """
  Decodes all entries into a list.

  Uses sequential binary walking for maximum throughput.
  Prefer lazy iteration via `stream/1` for large groups when
  you don't need all entries.
  """
  @spec to_list(t()) :: [map()]
  def to_list(%__MODULE__{num_in_group: 0}), do: []

  # Version-aware slow path: historical writer used a smaller entry size than the
  # current entry layout. The batch fast path strides by the current entry size
  # and would misalign on shorter entries, so decode each entry individually and
  # pad it up to the current size before decoding.
  def to_list(%__MODULE__{
        binary: binary,
        num_in_group: n,
        block_length: bl,
        entries_offset: offset,
        entry_decoder: decoder,
        current_block_length: current_bl,
        null_block: null_block
      })
      when is_integer(current_bl) and current_bl > bl do
    data = binary_part(binary, offset, n * bl)
    decode_all_padded(data, bl, current_bl, null_block, decoder, [])
  end

  def to_list(%__MODULE__{
        batch_decoder: batch_fn,
        binary: binary,
        num_in_group: n,
        block_length: bl,
        entries_offset: offset
      })
      when is_function(batch_fn, 2) do
    data = binary_part(binary, offset, n * bl)
    batch_fn.(data, [])
  end

  def to_list(%__MODULE__{
        binary: binary,
        num_in_group: n,
        block_length: bl,
        entries_offset: offset,
        entry_decoder: decoder
      }) do
    data = binary_part(binary, offset, n * bl)
    decode_all_sequential(data, bl, decoder, [])
  end

  defp decode_all_sequential(<<>>, _bl, _decoder, acc), do: :lists.reverse(acc)

  defp decode_all_sequential(data, bl, decoder, acc) do
    <<entry::binary-size(^bl), rest::binary>> = data
    {:ok, decoded} = decoder.(entry)
    decode_all_sequential(rest, bl, decoder, [decoded | acc])
  end

  defp decode_all_padded(<<>>, _bl, _current_bl, _null_block, _decoder, acc),
    do: :lists.reverse(acc)

  defp decode_all_padded(data, bl, current_bl, null_block, decoder, acc) do
    <<entry::binary-size(^bl), rest::binary>> = data
    padded = pad_entry(entry, bl, current_bl, null_block)
    {:ok, decoded} = decoder.(padded)
    decode_all_padded(rest, bl, current_bl, null_block, decoder, [decoded | acc])
  end

  # ============================================================================
  # Parallel Decoding
  # ============================================================================

  @parallel_threshold_bytes 256_000

  @doc """
  Decodes multiple groups in parallel, one process per group.

  Each group is decoded in a separate process with a pre-sized heap
  (avoids GC during decode). The binary is shared via zero-copy
  (BEAM shared binary heap for binaries >64 bytes).

  Falls back to sequential `to_list/1` when total data is below
  the parallel threshold (#{@parallel_threshold_bytes} bytes).

  ## Options

  - `:threshold` — minimum total bytes to trigger parallel decode
    (default: #{@parallel_threshold_bytes}). Set to `0` to always parallelize.

  ## Example

      {:ok, decoded} = MyCodec.decode(binary)

      [balances, orders] =
        GridCodec.Group.to_lists_parallel([decoded.balances, decoded.open_orders])
  """
  @spec to_lists_parallel([t()], keyword()) :: [[map()]]
  def to_lists_parallel(groups, opts \\ [])

  def to_lists_parallel([], _opts), do: []

  def to_lists_parallel(groups, opts) when is_list(groups) do
    threshold = Keyword.get(opts, :threshold, @parallel_threshold_bytes)

    total_bytes =
      Enum.reduce(groups, 0, fn %__MODULE__{num_in_group: n, block_length: bl}, acc ->
        acc + n * bl
      end)

    if total_bytes < threshold do
      Enum.map(groups, &to_list/1)
    else
      parent = self()

      refs =
        Enum.map(groups, fn group ->
          ref = make_ref()
          heap_est = group.num_in_group * 100 + 1000

          :erlang.spawn_opt(
            fn -> send(parent, {ref, to_list(group)}) end,
            [{:min_heap_size, heap_est}, {:fullsweep_after, 0}, {:priority, :high}]
          )

          ref
        end)

      Enum.map(refs, fn ref ->
        receive do
          {^ref, result} -> result
        end
      end)
    end
  end

  # ============================================================================
  # Utilities
  # ============================================================================

  @doc """
  Returns the total byte size of the group (header + all entries).
  """
  @spec total_size(t()) :: non_neg_integer()
  def total_size(%__MODULE__{num_in_group: n, block_length: bl}) do
    @header_size + n * bl
  end

  @doc """
  Returns the header size in bytes.
  """
  @spec header_size() :: pos_integer()
  def header_size, do: @header_size

  @doc """
  Maximum number of entries (u16 limit).
  """
  @spec max_entries() :: pos_integer()
  def max_entries, do: @max_u16

  @doc """
  Maximum entry size in bytes (u16 limit).
  """
  @spec max_entry_size() :: pos_integer()
  def max_entry_size, do: @max_u16

  @doc """
  Returns remaining binary after the group.

  Useful for parsing multiple consecutive groups.
  """
  @spec rest(t()) :: binary()
  def rest(%__MODULE__{binary: binary, num_in_group: n, block_length: bl}) do
    skip = @header_size + n * bl
    total_size = Kernel.byte_size(binary)

    if skip > total_size do
      raise ArgumentError,
            "Invalid group bounds: skip #{skip} exceeds binary size #{total_size}"
    end

    binary_part(binary, skip, total_size - skip)
  end
end
