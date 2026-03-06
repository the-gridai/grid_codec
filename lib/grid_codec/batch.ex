defmodule GridCodec.Batch do
  @moduledoc """
  Heterogeneous batches of GridCodec structs.

  A batch holds an ordered sequence of entries that may be different struct types,
  all from a compile-time `any_of:` set. Entries preserve insertion order.

  ## Strategies

  Batches support two encoding strategies, chosen at compile time:

  | Property | `:padded_union` (default) | `:typed_frames` |
  |----------|--------------------------|-----------------|
  | Random access | O(1) from raw binary | O(1) after offset index built on decode |
  | Wire size | `n × (max_block + 5)` | `8 + Σ(payload_i + 7)` |
  | Per-entry overhead | 5 bytes (seq + tag) + padding | 7 bytes (seq + tag + len) |
  | Decode cost | Lazy — no upfront work | Builds offset index (one scan of frame headers) |
  | Best for | Similar-size types, random access | Varied-size types, sequential streaming |

  ### When to use `:padded_union`

  - Types in the `any_of` set have similar `block_length` values
  - You need O(1) random access from the raw binary (no decode step)
  - Wire size overhead from padding is acceptable

  ### When to use `:typed_frames`

  - Types have very different sizes (e.g., 24-byte vs 80-byte payloads)
  - Primary access pattern is sequential streaming (`stream/1`)
  - Wire size matters (e.g., large batches crossing process/network boundaries)
  - Padding waste ratio `max_block / min_block > 3`

  ### Size comparison example

  Given SmallCmd (24B), MediumCmd (48B), LargeCmd (80B) with 8189 entries:

      :padded_union  → 8189 × (80 + 5) = 696,065 bytes
      :typed_frames  → 8 + 8189 × (avg ~52 + 7) ≈ 491,348 bytes  (29% smaller)

  ## Wire Formats

  ### Padded Union (`:padded_union`)

      ┌───────────────────────────────────────────────────────────┐
      │ Group Header (4 bytes)                                     │
      │  envelopeSize (u16 LE) │ numEntries (u16 LE)               │
      ├───────────────────────────────────────────────────────────┤
      │ Entry[0] (envelopeSize bytes)                              │
      │  seq_index (u32) │ type_tag (u8) │ payload │ zero-padding  │
      ├───────────────────────────────────────────────────────────┤
      │ Entry[1] ...                                               │
      └───────────────────────────────────────────────────────────┘

  ### Typed Frames (`:typed_frames`)

      ┌───────────────────────────────────────────────────────────┐
      │ Batch Header (8 bytes)                                     │
      │  bodySize (u32 LE) │ numEntries (u32 LE)                   │
      ├───────────────────────────────────────────────────────────┤
      │ Frame[0]                                                   │
      │  seq (u32) │ tag (u8) │ payloadLen (u16) │ payload         │
      ├───────────────────────────────────────────────────────────┤
      │ Frame[1] ...                                               │
      └───────────────────────────────────────────────────────────┘

  ## DSL Usage

      defcodec do
        field :market_id, :uuid

        # Default: padded union (O(1) random access, fixed-size entries)
        batch :commands, any_of: [PlaceOrder, CancelOrder, ReplaceOrder]

        # Or: typed frames (compact wire size, sequential streaming)
        batch :commands, any_of: [PlaceOrder, CancelOrder, ReplaceOrder],
                         strategy: :typed_frames
      end

  ## Access API (same for both strategies)

      {:ok, data} = MarketCommands.decode(binary)

      GridCodec.Batch.count(data.commands)                        # O(1)
      GridCodec.Batch.get(data.commands, 0)                       # O(1) random access
      GridCodec.Batch.stream(data.commands) |> Enum.take(10)      # lazy ordered stream
      GridCodec.Batch.by_type(data.commands, PlaceOrder)          # type filtering
      GridCodec.Batch.to_list(data.commands)                      # decode all
  """

  @enforce_keys [:impl, :strategy, :type_specs, :tag_to_module, :module_to_tag]
  defstruct [:impl, :strategy, :type_specs, :tag_to_module, :module_to_tag]

  @type type_spec ::
          {tag :: non_neg_integer(), module :: module(), block_length :: non_neg_integer()}

  @type t :: %__MODULE__{
          impl: GridCodec.Group.t() | GridCodec.Batch.TypedFrames.t(),
          strategy: :padded_union | :typed_frames,
          type_specs: [type_spec()],
          tag_to_module: %{non_neg_integer() => module()},
          module_to_tag: %{module() => non_neg_integer()}
        }

  @doc """
  Wraps a decoded `GridCodec.Group` in a Batch (padded_union strategy).
  """
  @spec wrap(GridCodec.Group.t(), [type_spec()]) :: t()
  def wrap(%GridCodec.Group{} = group, type_specs) do
    %__MODULE__{
      impl: group,
      strategy: :padded_union,
      type_specs: type_specs,
      tag_to_module: Map.new(type_specs, fn {tag, mod, _bl} -> {tag, mod} end),
      module_to_tag: Map.new(type_specs, fn {tag, mod, _bl} -> {mod, tag} end)
    }
  end

  @doc """
  Wraps a decoded `GridCodec.Batch.TypedFrames` struct in a Batch.
  """
  @spec wrap_typed_frames(GridCodec.Batch.TypedFrames.t(), [type_spec()]) :: t()
  def wrap_typed_frames(%GridCodec.Batch.TypedFrames{} = tf, type_specs) do
    %__MODULE__{
      impl: tf,
      strategy: :typed_frames,
      type_specs: type_specs,
      tag_to_module: Map.new(type_specs, fn {tag, mod, _bl} -> {tag, mod} end),
      module_to_tag: Map.new(type_specs, fn {tag, mod, _bl} -> {mod, tag} end)
    }
  end

  @doc "Returns the number of entries in the batch. O(1) for both strategies."
  @spec count(t()) :: non_neg_integer()
  def count(%__MODULE__{strategy: :padded_union, impl: group}),
    do: GridCodec.Group.count(group)

  def count(%__MODULE__{strategy: :typed_frames, impl: tf}),
    do: GridCodec.Batch.TypedFrames.count(tf)

  @doc """
  Gets the entry at the given index.

  O(1) for both strategies — padded_union computes offset arithmetically,
  typed_frames uses a pre-built offset index.

  Returns `{:ok, {seq_index, type_tag, decoded_struct}}`.
  """
  @spec get(t(), non_neg_integer()) ::
          {:ok, {non_neg_integer(), non_neg_integer(), map()}} | {:error, term()}
  def get(%__MODULE__{strategy: :padded_union, impl: group}, index),
    do: GridCodec.Group.get_entry(group, index)

  def get(%__MODULE__{strategy: :typed_frames, impl: tf}, index),
    do: GridCodec.Batch.TypedFrames.get(tf, index)

  @doc """
  Returns a lazy stream of `{seq_index, type_tag, decoded_struct}` tuples
  in insertion order.
  """
  @spec stream(t()) :: Enumerable.t()
  def stream(%__MODULE__{strategy: :padded_union, impl: group}),
    do: GridCodec.Group.stream(group)

  def stream(%__MODULE__{strategy: :typed_frames, impl: tf}),
    do: GridCodec.Batch.TypedFrames.stream(tf)

  @doc """
  Returns all entries of the given type module.

  Scans all entries and filters by type tag. O(n) for both strategies.
  """
  @spec by_type(t(), module()) :: [map()]
  def by_type(%__MODULE__{strategy: :padded_union} = batch, module) when is_atom(module) do
    target_tag = Map.fetch!(batch.module_to_tag, module)

    batch
    |> stream()
    |> Enum.reduce([], fn
      {_seq, ^target_tag, entry}, acc -> [entry | acc]
      _, acc -> acc
    end)
    |> :lists.reverse()
  end

  def by_type(%__MODULE__{strategy: :typed_frames} = batch, module) when is_atom(module) do
    target_tag = Map.fetch!(batch.module_to_tag, module)
    GridCodec.Batch.TypedFrames.by_type(batch.impl, target_tag)
  end

  @doc "Decodes all entries into a list of `{seq, tag, struct}` tuples in order."
  @spec to_list(t()) :: [{non_neg_integer(), non_neg_integer(), map()}]
  def to_list(%__MODULE__{strategy: :padded_union, impl: group}),
    do: GridCodec.Group.to_list(group)

  def to_list(%__MODULE__{strategy: :typed_frames, impl: tf}),
    do: GridCodec.Batch.TypedFrames.to_list(tf)

  @doc "Returns the binary size of the batch section."
  @spec wire_size(t()) :: non_neg_integer()
  def wire_size(%__MODULE__{strategy: :padded_union, impl: group}),
    do: GridCodec.Group.total_size(group)

  def wire_size(%__MODULE__{strategy: :typed_frames, impl: tf}),
    do: GridCodec.Batch.TypedFrames.wire_size(tf)

  @doc "Returns the strategy used by this batch."
  @spec strategy(t()) :: :padded_union | :typed_frames
  def strategy(%__MODULE__{strategy: s}), do: s

  @doc false
  def envelope_overhead, do: 5
end
