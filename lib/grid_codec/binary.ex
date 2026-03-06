defmodule GridCodec.Binary do
  @moduledoc """
  Utilities for managing binary memory lifecycle with GridCodec.

  ## The Sub-Binary Retention Problem

  When you extract a field from a GridCodec binary using `get/2`, binary-typed
  fields (`:uuid`, `char_array`) return **sub-binaries** — lightweight references
  pointing into the original encoded binary. This is fast (zero-copy) but means
  the entire original binary stays alive in memory as long as any sub-binary
  reference exists.

  This matters when you:

  - Extract a small field (e.g., a 16-byte UUID) from a large binary and
    discard the original — the original stays alive
  - Scan a large group, collect one field per entry — every group binary
    stays pinned
  - Use `GridCodec.Match` with `select:` on binary fields — extracted values
    are sub-binaries of the matched binary

  ## Solutions

  ### Option 1: `get/2` with `copy: true`

  For single field extraction, use the `:copy` option:

      require MyCodec
      uuid = MyCodec.get(binary, :trace_id, copy: true)

  This wraps the result in `:binary.copy/1`, creating an independent copy
  that doesn't retain the original. Safe on any field type — non-binary
  values pass through unchanged.

  ### Option 2: `detach/1` for decoded structs

  After full decode, detach all binary fields at once:

      {:ok, struct} = MyCodec.decode(large_binary)
      struct = GridCodec.Binary.detach(struct)

  This copies every binary-valued field in the struct, releasing references
  to the original encoded binary.

  ## When NOT to Use

  Skip `copy:` / `detach/1` when:

  - The original binary is still in scope and needed
  - The binary is small (<= 64 bytes) — it's already a heap binary, not
    reference-counted
  - You're immediately forwarding the result (sub-binary is fine for short-lived use)
  - The field type is `:uuid_string` — `getter_ast` already produces an independent
    formatted string, not a sub-binary

  ## Background: BEAM Binary Memory

  Binaries > 64 bytes are **reference-counted** (refc binaries). The payload lives
  in the binary allocator, and each process holds a small ProcBin reference on its
  heap. Sub-binaries from pattern matching (like `get/2` produces) increase the
  refcount, keeping the entire original alive until all references are GC'd.

  See [The BEAM Book — Memory](https://github.com/happi/theBeamBook/blob/master/chapters/memory.asciidoc)
  for the full explanation.
  """

  @doc """
  Copies all binary-valued fields in a struct, releasing sub-binary references.

  Walks the struct fields and calls `:binary.copy/1` on any value that is a
  binary. This detaches sub-binary references from the original encoded data,
  allowing the original to be garbage collected.

  Non-binary values (integers, atoms, nil, floats) pass through unchanged.

  ## Examples

      {:ok, struct} = MyCodec.decode(large_binary)
      struct = GridCodec.Binary.detach(struct)
      # large_binary can now be GC'd even if struct is kept

  ## Performance

  Adds one `:binary.copy/1` call per binary field. For a struct with 2 UUID
  fields, this is ~40ns total overhead — negligible compared to the memory
  savings from releasing a large original binary.
  """
  @spec detach(struct()) :: struct()
  def detach(%module{} = struct) do
    fields =
      if function_exported?(module, :__fields__, 0) do
        module.__fields__()
      else
        Map.keys(struct) -- [:__struct__]
      end

    Enum.reduce(fields, struct, fn field, acc ->
      case Map.get(acc, field) do
        val when is_binary(val) and byte_size(val) > 0 ->
          %{acc | field => :binary.copy(val)}

        _ ->
          acc
      end
    end)
  end

  @doc """
  Copies a single binary value, detaching it from any parent binary.

  Equivalent to `:binary.copy/1` but handles `nil` gracefully.

  ## Examples

      uuid = GridCodec.Binary.copy_field(MyCodec.get(bin, :id))
  """
  @spec copy_field(binary() | nil) :: binary() | nil
  def copy_field(nil), do: nil
  def copy_field(val) when is_binary(val), do: :binary.copy(val)
  def copy_field(val), do: val
end
