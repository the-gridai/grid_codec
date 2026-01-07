defmodule GridCodec.Group do
  @moduledoc """
  Repeating groups for arrays of fixed-size entries.

  Groups enable encoding variable-length arrays where each entry has
  the same structure. This is ideal for collections, batch events,
  nested lists, and similar use cases.

  ## Wire Format

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

  ## Header Format (4 bytes)

  - `blockLength` (u16 LE): Size of each entry in bytes (max 65,535)
  - `numInGroup` (u16 LE): Number of entries (max 65,535)

  ## Zero-Copy Access

  Groups support O(1) random access to any entry:

      {:ok, group} = GridCodec.Group.parse(binary, entry_decoder)

      # Get count without iteration
      count = GridCodec.Group.count(group)

      # Direct access to entry at index
      {:ok, entry} = GridCodec.Group.get_entry(group, 42)

      # Access field within entry at index
      {:ok, price} = GridCodec.Group.get_field(group, 42, :price)

  ## Lazy Iteration

  Groups are lazy - entries are only decoded when accessed:

      # Stream interface for lazy iteration
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

  ## Usage Example

      defmodule OrderBook do
        use GridCodec.Struct, template_id: 1, schema_id: 100

        defcodec do
          field :symbol, :uuid
          field :timestamp, :u64

          group :bids, entry_encoder: &encode_level/1, entry_decoder: &decode_level/1 do
            field :price, :u64
            field :quantity, :u32
          end

          group :asks, entry_encoder: &encode_level/1, entry_decoder: &decode_level/1 do
            field :price, :u64
            field :quantity, :u32
          end
        end

        defp encode_level(%{price: p, quantity: q}), do: <<p::little-64, q::little-32>>
        defp decode_level(<<p::little-64, q::little-32>>), do: {:ok, %{price: p, quantity: q}}
      end

      # Decode fully to access groups
      {:ok, order_book} = OrderBook.decode(binary)
      bids = order_book.bids

      # Count without full iteration
      count = GridCodec.Group.count(bids)

      # Random access to entries
      {:ok, top_bid} = GridCodec.Group.get_entry(bids, 0)
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
          entry_decoder: (binary() -> {:ok, map()} | {:error, term()})
        }

  defstruct [:binary, :num_in_group, :block_length, :entries_offset, :entry_decoder]

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

  def get_entry(
        %__MODULE__{
          binary: binary,
          block_length: block_length,
          entries_offset: offset,
          entry_decoder: decoder
        },
        index
      ) do
    entry_offset = offset + index * block_length
    entry_binary = binary_part(binary, entry_offset, block_length)
    decoder.(entry_binary)
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

  Use sparingly - prefer lazy iteration for large groups.
  """
  @spec to_list(t()) :: [map()]
  def to_list(group), do: map(group, & &1)

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
    binary_part(binary, skip, Kernel.byte_size(binary) - skip)
  end
end
