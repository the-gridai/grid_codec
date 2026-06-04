defmodule NilAtomRepro2 do
  @moduledoc """
  Classifies compile-time literal shapes (similar to a macro helper).
  """

  def classify_literal(value) do
    cond do
      is_nil(value) ->
        :nil_literal

      is_integer(value) ->
        :integer_literal

      value === true or value === false ->
        :boolean_literal

      # nil is an atom; we still document that nil was handled above
      is_atom(value) ->
        :atom_literal

      is_binary(value) ->
        :binary_literal

      true ->
        :not_literal
    end
  end
end
