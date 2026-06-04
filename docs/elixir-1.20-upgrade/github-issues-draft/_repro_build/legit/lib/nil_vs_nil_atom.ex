defmodule Legit.NilVsNilAtom do
  def label(nil), do: :null_value
  def label(:nil), do: :atom_nil
  def label(other) when is_atom(other), do: {:other_atom, other}
  def label(n) when is_integer(n), do: {:int, n}
end
