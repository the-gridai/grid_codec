defmodule NilAtomDisjoint do
  @moduledoc """
  Mirrors GridCodec.Struct.Compiler.encode_literal_for_pattern/4 guard order
  (pre-fix), which triggered disjoint-comparison type warnings on 1.20.
  """

  def classify_literal(value) do
    cond do
      value == nil ->
        :nil_literal

      is_integer(value) ->
        :integer_literal

      value == true ->
        :true_literal

      value == false ->
        :false_literal

      is_atom(value) and not is_nil(value) ->
        :atom_literal

      is_binary(value) ->
        :binary_literal

      true ->
        :not_literal
    end
  end
end
