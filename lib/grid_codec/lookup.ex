defmodule GridCodec.Lookup do
  @moduledoc """
  Runtime helpers for codec-defined collection lookups.

  Lookups are Elixir-side alternate access paths over decoded `GridCodec.Group`
  and `GridCodec.Batch` values. They are not part of the wire protocol or
  `.grid` schema format.

  ## Features

  - Named accessors generated from `lookups do`
  - Shared runtime engine for group and batch sources
  - Keyed map and filtered list projections
  - Keyed map projections with last-write-wins semantics

  ## Example

      {:ok, account} = MyCodec.decode(binary)
      {:ok, reservations_by_id} = MyCodec.reservations_by_id(account)

  The generated codec helper delegates into this module with a normalized lookup
  spec. Most consumers should use the codec-level helper, not call
  `GridCodec.Lookup` directly.
  """

  @typedoc """
  Normalized runtime lookup specification.
  """
  @type spec :: %{
          required(:name) => atom(),
          required(:source) => {:group | :batch, atom()},
          required(:into) => :list | :map,
          required(:keys) => [{:all, atom()} | {module(), atom()}],
          required(:filters) => [{:eq, atom(), term()}]
        }

  @doc """
  Applies a normalized lookup spec to a group source.

  Generated codec helpers use this to build lookups from a `GridCodec.Group.t()`
  or a pre-materialized list of group entries.
  """
  @spec build_group(GridCodec.Group.t() | list(), spec()) ::
          {:ok, list() | map()} | {:error, term()}
  def build_group(source, spec)

  def build_group(%GridCodec.Group{} = group, spec) do
    reduce_enum(GridCodec.Group.stream(group), spec)
  end

  def build_group(entries, spec) when is_list(entries) do
    reduce_enum(entries, spec)
  end

  def build_group(other, spec) do
    {:error, {:invalid_lookup_source, spec.name, {:group, other}}}
  end

  @doc """
  Applies a normalized lookup spec to a batch source.

  Generated codec helpers use this to build lookups from a `GridCodec.Batch.t()`
  or a pre-materialized list of `{seq, tag, struct}` tuples.
  """
  @spec build_batch(GridCodec.Batch.t() | list(), spec()) ::
          {:ok, list() | map()} | {:error, term()}
  def build_batch(source, spec)

  def build_batch(%GridCodec.Batch{} = batch, spec) do
    reduce_enum(GridCodec.Batch.stream(batch), spec)
  end

  def build_batch(entries, spec) when is_list(entries) do
    reduce_enum(entries, spec)
  end

  def build_batch(other, spec) do
    {:error, {:invalid_lookup_source, spec.name, {:batch, other}}}
  end

  defp reduce_enum(enum, spec) do
    init = init_acc(spec.into)

    case Enum.reduce_while(enum, {:ok, init}, fn raw_entry, {:ok, acc} ->
           reduce_step(unwrap_entry(raw_entry), acc, spec)
         end) do
      {:ok, acc} ->
        {:ok, finalize_acc(acc, spec.into)}

      {:error, _} = error ->
        error
    end
  end

  defp reduce_step(entry, acc, spec) do
    cond do
      not passes_filters?(entry, spec.filters) ->
        {:cont, {:ok, acc}}

      spec.into == :list ->
        {:cont, {:ok, [entry | acc]}}

      true ->
        reduce_map_step(entry, acc, spec)
    end
  end

  defp reduce_map_step(entry, acc, spec) do
    case extract_key(entry, spec.keys) do
      {:ok, key} ->
        {:ok, next_acc} = put_mapped(acc, key, entry)
        {:cont, {:ok, next_acc}}

      {:error, _} = error ->
        {:halt, error}
    end
  end

  defp unwrap_entry({_seq, _tag, entry}), do: entry
  defp unwrap_entry(entry), do: entry

  defp init_acc(:list), do: []
  defp init_acc(:map), do: %{}

  defp finalize_acc(acc, :list), do: :lists.reverse(acc)
  defp finalize_acc(acc, :map), do: acc

  defp passes_filters?(_entry, []), do: true

  defp passes_filters?(entry, filters) do
    Enum.all?(filters, fn {:eq, field, expected} ->
      Map.get(entry, field) == expected
    end)
  end

  defp extract_key(entry, [{:all, field}]) do
    {:ok, Map.get(entry, field)}
  end

  defp extract_key(%{__struct__: module} = entry, specs) do
    case Enum.find(specs, fn
           {:all, _field} -> true
           {^module, _field} -> true
           _ -> false
         end) do
      nil ->
        {:error, {:missing_batch_key_spec, module}}

      {:all, field} ->
        {:ok, Map.get(entry, field)}

      {^module, field} ->
        {:ok, Map.get(entry, field)}
    end
  end

  defp extract_key(entry, specs) when is_map(entry) do
    case Enum.find(specs, fn
           {:all, _field} -> true
           _ -> false
         end) do
      nil -> {:error, {:missing_key_spec, entry}}
      {:all, field} -> {:ok, Map.get(entry, field)}
    end
  end

  defp put_mapped(acc, key, entry), do: {:ok, Map.put(acc, key, entry)}
end
