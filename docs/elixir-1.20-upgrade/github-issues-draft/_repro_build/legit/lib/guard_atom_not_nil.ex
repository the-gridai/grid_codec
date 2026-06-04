defmodule Legit.GuardAtomNotNil do
  def only_non_nil_atoms(list) do
    Enum.filter(list, &(is_atom(&1) and &1 != nil))
  end
end
