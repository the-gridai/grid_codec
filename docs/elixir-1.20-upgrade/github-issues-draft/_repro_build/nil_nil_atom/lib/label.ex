defmodule NilNilAtom.Label do
  @moduledoc """
  Developers sometimes treat `nil` and `:nil` as different cases.
  In Elixir they are the same value (nil is the atom :nil).
  """

  # Common style: explicit nil, then catch atoms
  def describe(nil), do: "missing"
  def describe(:nil), do: "atom :nil"  # looks distinct, is not
  def describe(atom) when is_atom(atom), do: "other atom: #{atom}"
  def describe(other), do: "not atom: #{inspect(other)}"
end
