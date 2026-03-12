defmodule GridCodec.View do
  @moduledoc """
  Backward-compatible alias for `GridCodec.Lookup`.

  Prefer `GridCodec.Lookup` and the `lookups do` DSL for new code.
  """
  @type spec :: GridCodec.Lookup.spec()

  defdelegate build_group(source, spec), to: GridCodec.Lookup
  defdelegate build_batch(source, spec), to: GridCodec.Lookup
end
